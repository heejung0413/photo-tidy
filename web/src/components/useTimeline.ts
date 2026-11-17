import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { CustomPlaceNames } from '../core/customNames'
import { placeKey } from '../core/placeKey'
import { PlaceNameLookup } from '../core/placeNameLookup'
import { days as buildDays, stopId } from '../core/timeline'
import { Tuning } from '../core/tuning'
import type { TimelineDay, TimelinePhoto, TimelineStop } from '../core/types'
import { reverseGeocode } from '../services/nominatim'
import { readPhoto } from '../services/readPhoto'
import { loadJSON, saveJSON, STORAGE_KEYS } from '../services/storage'

export interface Timeline {
  days: TimelineDay[]
  /** 화면에 보이는 순서대로의 머문 곳 전체. 번호는 이 순서를 따른다. */
  stops: TimelineStop[]
  photoCount: number
  /** 파일을 읽는 중이면 진행 상황. */
  reading: { done: number; total: number } | null
  /** 사진이 아니어서 건너뛴 파일 수. */
  skippedFiles: number
  /** 촬영 시각이 없어 파일 수정 시각을 쓴 사진 수. */
  fileTimePhotos: number
  addFiles: (files: File[]) => Promise<void>
  clear: () => void
  /** 1부터 시작하는 번호. */
  number: (stop: TimelineStop) => number
  title: (stop: TimelineStop) => string
  /** 직접 붙인 이름(이름 고치기 칸의 처음 값). */
  customName: (stop: TimelineStop) => string | null
  /**
   * 부르는 순간에 아는 이름(직접 붙인 이름 또는 받아 둔 이름).
   * 화면을 그린 뒤에 도착한 이름도 돌려주므로, 오래 걸리는 작업이 끝난 뒤에 불러도 된다.
   */
  latestName: (stop: TimelineStop) => string | null
  rename: (stop: TimelineStop, text: string) => void
  thumbnail: (photoId: string) => string | undefined
}

function loadPlaceNames(): Record<string, string> {
  const saved = loadJSON(STORAGE_KEYS.placeNames, {})
  if (typeof saved !== 'object' || saved === null) return {}
  return Object.fromEntries(Object.entries(saved).filter(([, name]) => typeof name === 'string')) as Record<string, string>
}

export function useTimeline(): Timeline {
  const [photos, setPhotos] = useState<TimelinePhoto[]>([])
  const [reading, setReading] = useState<Timeline['reading']>(null)
  const [skippedFiles, setSkippedFiles] = useState(0)
  const [fileTimePhotos, setFileTimePhotos] = useState(0)
  const [customNames, setCustomNames] = useState(() => CustomPlaceNames.fromJSON(loadJSON(STORAGE_KEYS.customNames, [])))
  /** 받아 온 이름. placeKey → 이름. */
  const [placeNames, setPlaceNames] = useState(loadPlaceNames)
  /** 사진 id → 화면에 그릴 주소. */
  const thumbnails = useRef(new Map<string, string>())
  /** "전부 지우기"를 누를 때마다 올라간다. 그 전에 읽기 시작한 사진을 버리는 데 쓴다. */
  const generation = useRef(0)
  /** 사진 묶음을 차례로 읽기 위한 줄. 앞 묶음이 끝나야 다음 묶음을 읽는다. */
  const queue = useRef<Promise<void>>(Promise.resolve())
  /** 화면을 그린 뒤에도 최신 값을 읽을 수 있게 둔다. */
  const latestCustomNames = useRef(customNames)
  useEffect(() => {
    latestCustomNames.current = customNames
  }, [customNames])

  const lookup = useRef<PlaceNameLookup | null>(null)
  if (lookup.current === null) {
    lookup.current = new PlaceNameLookup({
      cache: placeNames,
      lookup: reverseGeocode,
      minInterval: Tuning.placeNameInterval,
      onChange: (cache) => saveJSON(STORAGE_KEYS.placeNames, cache),
    })
  }

  const timelineDays = useMemo(() => buildDays(photos), [photos])
  const stops = useMemo(() => timelineDays.flatMap((day) => day.stops), [timelineDays])
  const order = useMemo(() => new Map(stops.map((stop, index) => [stopId(stop), index + 1])), [stops])

  // 위치가 있는 머문 곳의 이름을 하나씩 받아 온다.
  useEffect(() => {
    let cancelled = false
    void (async () => {
      for (const stop of stops) {
        if (cancelled) return
        if (!stop.center) continue
        const key = placeKey(stop.center)
        const name = await lookup.current!.name(stop.center)
        if (cancelled) return
        if (name !== null) {
          setPlaceNames((names) => (names[key] === name ? names : { ...names, [key]: name }))
        }
      }
    })()
    return () => {
      cancelled = true
    }
  }, [stops])

  /** 사진 묶음 하나를 읽는다. 읽는 도중 "전부 지우기"를 누르면 읽은 것을 버린다. */
  const readBatch = useCallback(async (files: File[]) => {
    const started = generation.current
    const added: { photo: TimelinePhoto; file: File }[] = []
    const seen = new Set<string>()
    let skipped = 0
    let fileTime = 0
    setReading({ done: 0, total: files.length })
    for (const [index, file] of files.entries()) {
      const result = await readPhoto(file)
      if (generation.current !== started) return
      if (result === null) {
        skipped += 1
      } else if (!thumbnails.current.has(result.photo.id) && !seen.has(result.photo.id)) {
        // 같은 파일을 다시 올리면 한 번만 넣는다.
        seen.add(result.photo.id)
        added.push({ photo: result.photo, file })
        if (result.usedFileTime) fileTime += 1
      }
      setReading({ done: index + 1, total: files.length })
    }
    for (const { photo, file } of added) {
      thumbnails.current.set(photo.id, URL.createObjectURL(file))
    }
    setPhotos((current) => [...current, ...added.map((item) => item.photo)])
    // 읽지 못한 파일 안내는 방금 올린 묶음의 것만 보여 준다.
    setSkippedFiles(skipped)
    setFileTimePhotos((count) => count + fileTime)
    setReading(null)
  }, [])

  const addFiles = useCallback(
    (files: File[]) => {
      if (files.length === 0) return Promise.resolve()
      // 여러 묶음을 연달아 올려도 진행 표시가 섞이지 않게 차례로 읽는다.
      queue.current = queue.current.then(() => readBatch(files)).catch(() => {})
      return queue.current
    },
    [readBatch],
  )

  const clear = useCallback(() => {
    generation.current += 1
    for (const url of thumbnails.current.values()) {
      URL.revokeObjectURL(url)
    }
    thumbnails.current.clear()
    setPhotos([])
    setSkippedFiles(0)
    setFileTimePhotos(0)
    setReading(null)
  }, [])

  const number = useCallback((stop: TimelineStop) => order.get(stopId(stop)) ?? 0, [order])

  const knownName = useCallback(
    (stop: TimelineStop) => customNames.name(stop) ?? (stop.center ? (placeNames[placeKey(stop.center)] ?? null) : null),
    [customNames, placeNames],
  )

  const latestName = useCallback(
    (stop: TimelineStop) =>
      latestCustomNames.current.name(stop) ?? (stop.center ? lookup.current!.cachedName(stop.center) : null),
    [],
  )

  const title = useCallback(
    (stop: TimelineStop) => {
      const known = knownName(stop)
      if (known !== null) return known
      return stop.center ? `장소 ${order.get(stopId(stop)) ?? ''}`.trim() : '위치 정보 없음'
    },
    [knownName, order],
  )

  const rename = useCallback((stop: TimelineStop, text: string) => {
    setCustomNames((names) => {
      const next = names.rename(stop, text)
      saveJSON(STORAGE_KEYS.customNames, next)
      return next
    })
  }, [])

  return {
    days: timelineDays,
    stops,
    photoCount: photos.length,
    reading,
    skippedFiles,
    fileTimePhotos,
    addFiles,
    clear,
    number,
    title,
    customName: (stop) => customNames.name(stop),
    latestName,
    rename,
    thumbnail: (photoId) => thumbnails.current.get(photoId),
  }
}
