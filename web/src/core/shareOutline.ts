import type { Coordinate, TimelineDay, TimelineStop } from './types'

export interface ShareStop {
  stop: TimelineStop
  number: number
  title: string
  /** 썸네일로 쓸 사진. */
  thumbnailIDs: string[]
  /** 썸네일에 담지 못한 사진 수. */
  moreCount: number
}

export interface ShareSection {
  day: string
  stops: ShareStop[]
}

export interface SharePin {
  number: number
  coordinate: Coordinate
}

/**
 * 공유 이미지에 담을 내용. 만드는 순간의 값을 모두 담아 두므로,
 * 이미지를 만드는 동안 화면 상태가 바뀌어도 내용이 섞이지 않는다.
 */
export interface ShareOutline {
  sections: ShareSection[]
  /** 날짜별 경로. 위치 있는 머문 곳만. */
  routes: SharePin[][]
  /** maxStops를 넘어 담지 못한 머문 곳 수. */
  hiddenStops: number
  /** 담지 못한 머문 곳까지 포함한 전체 사진 수. */
  photoCount: number
}

export function makeShareOutline(
  days: TimelineDay[],
  options: { maxStops: number; thumbnailsPerStop: number; title: (stop: TimelineStop) => string },
): ShareOutline {
  const sections: ShareSection[] = []
  const routes: SharePin[][] = []
  let number = 0
  for (const day of days) {
    if (number >= options.maxStops) break
    const stops: ShareStop[] = []
    const route: SharePin[] = []
    for (const stop of day.stops) {
      if (number >= options.maxStops) break
      number += 1
      stops.push({
        stop,
        number,
        title: options.title(stop),
        thumbnailIDs: stop.photos.slice(0, options.thumbnailsPerStop).map((photo) => photo.id),
        moreCount: Math.max(0, stop.photos.length - options.thumbnailsPerStop),
      })
      if (stop.center) {
        route.push({ number, coordinate: stop.center })
      }
    }
    sections.push({ day: day.day, stops })
    routes.push(route)
  }
  const allStops = days.flatMap((day) => day.stops)
  return {
    sections,
    routes,
    hiddenStops: allStops.length - number,
    photoCount: allStops.reduce((sum, stop) => sum + stop.photos.length, 0),
  }
}

/**
 * 이미지를 만드는 사이 도착한 이름을 반영한다. title이 null을 주는 머문 곳은 처음 제목을 둔다.
 * 담긴 머문 곳과 순번은 바뀌지 않는다.
 */
export function retitled(outline: ShareOutline, title: (stop: TimelineStop) => string | null): ShareOutline {
  return {
    ...outline,
    sections: outline.sections.map((section) => ({
      ...section,
      stops: section.stops.map((item) => ({ ...item, title: title(item.stop) ?? item.title })),
    })),
  }
}
