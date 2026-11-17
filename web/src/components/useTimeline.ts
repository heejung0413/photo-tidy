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
import { makeThumbnail } from '../services/thumbnails'

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
  /** 작게 줄인 그림의 주소. 아직 만들지 못했거나 브라우저가 그리지 못하는 형식이면 undefined. */
  thumbnail: (photoId: string) => string | undefined
  /** 썸네일 주소. 아직 만들지 않았으면 만들 때까지 기다린다(공유 이미지용). 그리지 못하는 사진이면 undefined. */
  ensureThumbnail: (photoId: string) => Promise<string | undefined>
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
  /** 사진 id → 작게 줄인 그림의 주소. 사진을 올린 뒤 하나씩 만들어 채운다. */
  const [thumbnails, setThumbnails] = useState<Record<string, string>>({})
  /** 만든 썸네일 주소 전부(지울 때 풀기 위해, 그리고 최신 값을 읽기 위해). */
  const thumbnailURLs = useRef(new Map<string, string>())
  /** 아직 썸네일을 만들지 않은 사진의 파일. */
  const pendingFiles = useRef(new Map<string, File>())
  /** 지금 만들고 있는 썸네일. 같은 사진을 두 번 만들지 않기 위해 둔다. */
  const makingThumbnails = useRef(new Map<string, Promise<string | undefined>>())
  /** 만들었지만 아직 화면 상태에 넣지 않은 썸네일. 여러 장을 모아 한 번에 넣는다. */
  const readyThumbnails = useRef<{ batch: Record<string, string>; timer: ReturnType<typeof setTimeout> | null }>({
    batch: {},
    timer: null,
  })
  /** 지금 들어 있는 사진 id. 같은 파일을 다시 올렸는지 보는 데 쓴다. */
  const knownIDs = useRef(new Set<string>())
  /** "전부 지우기"를 누를 때마다 올라간다. 그 전에 올린 사진을 버리는 데 쓴다. */
  const generation = useRef(0)
  /** 사진 묶음을 차례로 읽기 위한 줄. 앞 묶음을 다 읽어야 다음 묶음을 읽는다. */
  const queue = useRef<Promise<void>>(Promise.resolve())
  /** 썸네일을 차례로 만들기 위한 줄. 사진 읽기와 따로 돈다. */
  const thumbnailQueue = useRef<Promise<void>>(Promise.resolve())
  /** 이름을 받지 못한 곳이 남아 다시 물어볼 때마다 올라간다. */
  const [retryTick, setRetryTick] = useState(0)
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
    let retry: ReturnType<typeof setTimeout> | null = null
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
      // 요청이 실패했거나 쉬는 중이라 답을 받지 못한 곳이 남았으면, 잠시 뒤 다시 묻는다.
      if (stops.some((stop) => stop.center && lookup.current!.isUnknown(stop.center))) {
        retry = setTimeout(() => setRetryTick((tick) => tick + 1), Tuning.placeNameRetryDelay)
      }
    })()
    return () => {
      cancelled = true
      if (retry) clearTimeout(retry)
    }
  }, [stops, retryTick])

  /** 만든 썸네일을 화면 상태에 넣는다. 한 장씩 넣으면 그때마다 목록 전체를 다시 그리므로 모아서 넣는다. */
  const showThumbnail = useCallback((photoId: string, url: string) => {
    const ready = readyThumbnails.current
    ready.batch[photoId] = url
    if (ready.timer === null) {
      ready.timer = setTimeout(() => {
        const batch = ready.batch
        ready.batch = {}
        ready.timer = null
        setThumbnails((current) => ({ ...current, ...batch }))
      }, 100)
    }
  }, [])

  /**
   * 사진의 썸네일 주소. 아직 만들지 않았으면 지금 만든다.
   * 브라우저가 그리지 못하는 형식이거나 사진이 지워졌으면 undefined.
   */
  const ensureThumbnail = useCallback(
    (photoId: string): Promise<string | undefined> => {
      const made = thumbnailURLs.current.get(photoId)
      if (made) return Promise.resolve(made)
      const making = makingThumbnails.current.get(photoId)
      if (making) return making
      const file = pendingFiles.current.get(photoId)
      if (!file) return Promise.resolve(undefined)
      const started = generation.current
      const promise = makeThumbnail(file).then((url) => {
        if (generation.current !== started) {
          // 만드는 사이 "전부 지우기"를 눌렀다.
          if (url) URL.revokeObjectURL(url)
          return undefined
        }
        makingThumbnails.current.delete(photoId)
        pendingFiles.current.delete(photoId)
        if (!url) return undefined
        thumbnailURLs.current.set(photoId, url)
        showThumbnail(photoId, url)
        return url
      })
      makingThumbnails.current.set(photoId, promise)
      return promise
    },
    [showThumbnail],
  )

  /**
   * 사진 묶음 하나를 읽는다. started는 이 묶음을 올린 때의 generation이다.
   * 그 뒤로 "전부 지우기"를 눌렀으면(읽는 중이든 줄에서 기다리는 중이든) 버린다.
   */
  const readBatch = useCallback(
    async (files: File[], started: number) => {
      if (generation.current !== started) return
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
        } else if (!knownIDs.current.has(result.photo.id) && !seen.has(result.photo.id)) {
          // 같은 파일을 다시 올리면 한 번만 넣는다.
          seen.add(result.photo.id)
          added.push({ photo: result.photo, file })
          if (result.usedFileTime) fileTime += 1
        }
        setReading({ done: index + 1, total: files.length })
      }
      for (const { photo, file } of added) {
        knownIDs.current.add(photo.id)
        pendingFiles.current.set(photo.id, file)
      }
      setPhotos((current) => [...current, ...added.map((item) => item.photo)])
      // 읽지 못한 파일 안내는 방금 올린 묶음의 것만 보여 준다.
      setSkippedFiles(skipped)
      setFileTimePhotos((count) => count + fileTime)
      setReading(null)

      // 썸네일은 사진 읽기와 따로, 한 장씩 만든다(여러 장을 한꺼번에 풀면 메모리를 많이 쓴다).
      // 다음 묶음은 이 썸네일을 기다리지 않고 바로 읽는다.
      thumbnailQueue.current = thumbnailQueue.current.then(async () => {
        for (const { photo } of added) {
          if (generation.current !== started) return
          await ensureThumbnail(photo.id)
        }
      })
    },
    [ensureThumbnail],
  )

  const addFiles = useCallback(
    (files: File[]) => {
      if (files.length === 0) return Promise.resolve()
      const started = generation.current
      // 여러 묶음을 연달아 올려도 진행 표시가 섞이지 않게 차례로 읽는다.
      queue.current = queue.current.then(() => readBatch(files, started)).catch(() => {})
      return queue.current
    },
    [readBatch],
  )

  const clear = useCallback(() => {
    generation.current += 1
    for (const url of thumbnailURLs.current.values()) {
      URL.revokeObjectURL(url)
    }
    thumbnailURLs.current.clear()
    pendingFiles.current.clear()
    makingThumbnails.current.clear()
    readyThumbnails.current.batch = {}
    knownIDs.current.clear()
    setThumbnails({})
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
    thumbnail: (photoId) => thumbnails[photoId],
    ensureThumbnail,
  }
}
