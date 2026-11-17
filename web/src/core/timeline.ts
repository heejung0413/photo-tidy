import { Tuning } from './tuning'
import type { Coordinate, TimelineDay, TimelinePhoto, TimelineStop } from './types'

export const stopId = (stop: TimelineStop): string => stop.photos[0].id
export const stopStart = (stop: TimelineStop): number => stop.photos[0].takenAt
export const stopEnd = (stop: TimelineStop): number => stop.photos[stop.photos.length - 1].takenAt

/** 그날 머문 곳의 중심을 순서대로. 위치 없는 머문 곳은 뺀다. */
export function dayRoute(day: TimelineDay): Coordinate[] {
  return day.stops.flatMap((stop) => (stop.center ? [stop.center] : []))
}

/** 두 좌표 사이 거리(미터, 하버사인 공식). */
export function distance(a: Coordinate, b: Coordinate): number {
  const earthRadius = 6_371_000
  const toRadians = (degrees: number) => (degrees * Math.PI) / 180
  const lat1 = toRadians(a.latitude)
  const lat2 = toRadians(b.latitude)
  const dLat = lat2 - lat1
  const dLon = toRadians(b.longitude - a.longitude)
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2
  return 2 * earthRadius * Math.asin(Math.min(1, Math.sqrt(h)))
}

/** 사진을 시각순으로 보며, 현재 머문 곳 중심에서 radius를 벗어나면 새 머문 곳을 시작한다. */
export function stops(photos: TimelinePhoto[], radius: number = Tuning.stopRadius): TimelineStop[] {
  const result: TimelineStop[] = []
  let current: TimelinePhoto[] = []
  let located: Coordinate[] = []

  const center = (): Coordinate | null => {
    if (located.length === 0) return null
    return {
      latitude: located.reduce((sum, c) => sum + c.latitude, 0) / located.length,
      longitude: located.reduce((sum, c) => sum + c.longitude, 0) / located.length,
    }
  }
  const flush = () => {
    if (current.length === 0) return
    result.push({ photos: current, center: center() })
    current = []
    located = []
  }

  for (const photo of [...photos].sort((a, b) => a.takenAt - b.takenAt)) {
    if (photo.coordinate) {
      const now = center()
      if (now && distance(now, photo.coordinate) > radius) {
        flush()
      }
      located.push(photo.coordinate)
    }
    current.push(photo)
  }
  flush()
  return result
}

const dayFormatters = new Map<string, Intl.DateTimeFormat>()

/** 그 시간대에서의 달력 날짜. "2026-11-14". */
export function dayKey(ms: number, timeZone: string): string {
  let formatter = dayFormatters.get(timeZone)
  if (!formatter) {
    formatter = new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' })
    dayFormatters.set(timeZone, formatter)
  }
  return formatter.format(ms)
}

export const localTimeZone = (): string => Intl.DateTimeFormat().resolvedOptions().timeZone

/**
 * 여러 날 사진을 날짜별로 나눠 각각 머문 곳으로 묶는다. 날짜 오름차순.
 * 날이 바뀌면 같은 장소여도 새 머문 곳이 된다.
 */
export function days(
  photos: TimelinePhoto[],
  timeZone: string = localTimeZone(),
  radius: number = Tuning.stopRadius,
): TimelineDay[] {
  const byDay = new Map<string, TimelinePhoto[]>()
  for (const photo of photos) {
    const key = dayKey(photo.takenAt, timeZone)
    const list = byDay.get(key)
    if (list) {
      list.push(photo)
    } else {
      byDay.set(key, [photo])
    }
  }
  return [...byDay.keys()].sort().map((day) => ({ day, stops: stops(byDay.get(day) ?? [], radius) }))
}
