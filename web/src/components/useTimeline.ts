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
  /** 화면과 무관하게 지금 아는 이름(직접 붙인 이름 또는 받아 둔 이름). */
  knownName: (stop: TimelineStop) => string | null
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

  const addFiles = useCallback(async (files: File[]) => {
    if (files.length === 0) return
    setReading({ done: 0, total: files.length })
    const added: TimelinePhoto[] = []
    let skipped = 0
    let fileTime = 0
    for (const [index, file] of files.entries()) {
      const result = await readPhoto(file)
      if (result === null) {
        skipped += 1
      } else if (!thumbnails.current.has(result.photo.id)) {
        // 같은 파일을 다시 올리면 한 번만 넣는다.
        thumbnails.current.set(result.photo.id, URL.createObjectURL(file))
        added.push(result.photo)
        if (result.usedFileTime) fileTime += 1
      }
      setReading({ done: index + 1, total: files.length })
    }
    setPhotos((current) => [...current, ...added])
    setSkippedFiles((count) => count + skipped)
    setFileTimePhotos((count) => count + fileTime)
    setReading(null)
  }, [])

  const clear = useCallback(() => {
    for (const url of thumbnails.current.values()) {
      URL.revokeObjectURL(url)
    }
    thumbnails.current.clear()
    setPhotos([])
    setSkippedFiles(0)
    setFileTimePhotos(0)
  }, [])

  const number = useCallback((stop: TimelineStop) => order.get(stopId(stop)) ?? 0, [order])

  const knownName = useCallback(
    (stop: TimelineStop) => customNames.name(stop) ?? (stop.center ? (placeNames[placeKey(stop.center)] ?? null) : null),
    [customNames, placeNames],
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
    knownName,
    rename,
    thumbnail: (photoId) => thumbnails.current.get(photoId),
  }
}
