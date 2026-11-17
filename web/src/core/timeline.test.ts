import { describe, expect, test } from 'vitest'
import { dayKey, dayRoute, days, distance, stopEnd, stopId, stops, stopStart } from './timeline'
import type { TimelinePhoto, TimelineStop } from './types'

// Swift 테스트와 같은 기준 시각: 2001-01-01 00:00 UTC.
const REF = Date.UTC(2001, 0, 1)

/** 기준 시각에서 seconds초 뒤에 찍은 사진. latitude가 없으면 위치 없음. 위도 0.001도는 약 111m. */
function tp(id: string, seconds: number, latitude?: number): TimelinePhoto {
  return {
    id,
    takenAt: REF + seconds * 1000,
    coordinate: latitude === undefined ? null : { latitude, longitude: 127.0 },
  }
}

const ids = (list: TimelineStop[]) => list.map((stop) => stop.photos.map((photo) => photo.id))

describe('distance', () => {
  test('위도 0.001도는 약 111m', () => {
    const meters = distance({ latitude: 37.0, longitude: 127.0 }, { latitude: 37.001, longitude: 127.0 })
    expect(Math.abs(meters - 111.2)).toBeLessThan(0.5)
  })

  test('같은 점은 0이고, 방향을 바꿔도 같다', () => {
    const seongsu = { latitude: 37.5446, longitude: 127.0559 }
    const namsan = { latitude: 37.5512, longitude: 126.9882 }
    expect(distance(seongsu, seongsu)).toBeCloseTo(0, 3)
    expect(distance(seongsu, namsan)).toBeCloseTo(distance(namsan, seongsu), 3)
    expect(Math.abs(distance(seongsu, namsan) - 6010)).toBeLessThan(60)
  })
})

describe('stops', () => {
  test('사진이 없으면 머문 곳도 없다', () => {
    expect(stops([])).toEqual([])
  })

  test('반경 안의 사진은 한 곳이 된다', () => {
    const result = stops([tp('a', 0, 37.0), tp('b', 60, 37.001)], 200)
    expect(ids(result)).toEqual([['a', 'b']])
    expect(result[0].center?.latitude).toBeCloseTo(37.0005, 5)
    expect(stopStart(result[0])).toBe(REF)
    expect(stopEnd(result[0])).toBe(REF + 60_000)
  })

  test('반경을 벗어난 사진은 새 곳을 시작한다', () => {
    expect(ids(stops([tp('a', 0, 37.0), tp('b', 60, 37.01)], 200))).toEqual([['a'], ['b']])
  })

  test('같은 곳에 돌아와도 따로 센다', () => {
    const result = stops([tp('a', 0, 37.0), tp('b', 60, 37.01), tp('c', 120, 37.0)], 200)
    expect(ids(result)).toEqual([['a'], ['b'], ['c']])
  })

  test('위치 없는 사진은 지금 머문 곳에 들어간다', () => {
    const result = stops([tp('a', 0, 37.0), tp('b', 60), tp('c', 120, 37.01)], 200)
    expect(ids(result)).toEqual([['a', 'b'], ['c']])
  })

  test('앞쪽의 위치 없는 사진은 첫 위치 있는 곳에 합쳐진다', () => {
    const result = stops([tp('a', 0), tp('b', 60, 37.0)], 200)
    expect(ids(result)).toEqual([['a', 'b']])
    expect(result[0].center?.latitude).toBe(37.0)
  })

  test('전부 위치가 없으면 중심 없는 한 곳이 된다', () => {
    const result = stops([tp('a', 0), tp('b', 60)], 200)
    expect(ids(result)).toEqual([['a', 'b']])
    expect(result[0].center).toBeNull()
  })

  test('시각순으로 정렬해서 본다', () => {
    expect(ids(stops([tp('b', 60, 37.0), tp('a', 0, 37.0)], 200))).toEqual([['a', 'b']])
  })

  test('반경 경계', () => {
    const photos = [tp('a', 0, 37.0), tp('b', 60, 37.001)]
    expect(ids(stops(photos, 112))).toEqual([['a', 'b']])
    expect(ids(stops(photos, 110))).toEqual([['a'], ['b']])
  })

  test('중심은 평균이라, 조금씩 움직이면 한 곳으로 남는다', () => {
    // 한 번에 150m씩 움직여도 중심(평균)에서 200m를 넘지 않는다.
    const result = stops([tp('a', 0, 37.0), tp('b', 60, 37.00135), tp('c', 120, 37.0022)], 200)
    expect(ids(result)).toEqual([['a', 'b', 'c']])
  })

  test('머문 곳 id는 첫 사진 id', () => {
    const result = stops([tp('late', 60, 37.0), tp('early', 0, 37.0)])
    expect(result.map(stopId)).toEqual(['early'])
  })

  test('기본 반경은 200m', () => {
    // 위도 0.0017도 ≈ 189m, 0.0019도 ≈ 211m.
    expect(stops([tp('a', 0, 37.0), tp('b', 60, 37.0017)])).toHaveLength(1)
    expect(stops([tp('a', 0, 37.0), tp('b', 60, 37.0019)])).toHaveLength(2)
  })
})

describe('days', () => {
  test('사진이 없으면 날짜도 없다', () => {
    expect(days([], 'UTC')).toEqual([])
  })

  test('같은 장소여도 날이 바뀌면 나눈다', () => {
    const result = days([tp('a', 0, 37.0), tp('b', 86_399, 37.0), tp('c', 86_400, 37.0)], 'UTC', 200)
    expect(result.map((day) => ids(day.stops))).toEqual([[['a', 'b']], [['c']]])
    expect(result.map((day) => day.day)).toEqual(['2001-01-01', '2001-01-02'])
  })

  test('날짜순으로 정렬하고, 하루 안의 머문 곳은 유지한다', () => {
    const result = days([tp('d', 90_000, 37.0), tp('b', 60, 37.01), tp('a', 0, 37.0)], 'UTC', 200)
    expect(result.map((day) => ids(day.stops))).toEqual([[['a'], ['b']], [['d']]])
  })

  test('날짜 경계는 시간대를 따른다', () => {
    // 기준 시각은 서울 09:00. 15시간 뒤가 서울의 다음 날 0시다.
    const photos = [tp('a', 0), tp('b', 53_999), tp('c', 54_000)]
    expect(days(photos, 'Asia/Seoul').map((day) => ids(day.stops))).toEqual([[['a', 'b']], [['c']]])
    expect(days(photos, 'Asia/Seoul').map((day) => day.day)).toEqual(['2001-01-01', '2001-01-02'])
    expect(days(photos, 'UTC')).toHaveLength(1)
  })

  test('그날의 경로는 머문 곳 중심을 순서대로, 위치 없는 곳은 뺀다', () => {
    const result = days([tp('a', 0, 37.0), tp('b', 60, 37.01), tp('c', 86_400)], 'UTC', 200)
    expect(result.map((day) => dayRoute(day).map((c) => c.latitude))).toEqual([[37.0, 37.01], []])
  })
})

describe('dayKey', () => {
  test('시간대의 달력 날짜를 YYYY-MM-DD로', () => {
    expect(dayKey(Date.UTC(2026, 10, 14, 15, 0), 'Asia/Seoul')).toBe('2026-11-15')
    expect(dayKey(Date.UTC(2026, 10, 14, 15, 0), 'UTC')).toBe('2026-11-14')
    expect(dayKey(Date.UTC(2026, 0, 5, 3, 0), 'America/Los_Angeles')).toBe('2026-01-04')
  })
})
