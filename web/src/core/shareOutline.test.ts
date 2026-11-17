import { describe, expect, test } from 'vitest'
import { makeShareOutline, retitled } from './shareOutline'
import { stopId } from './timeline'
import type { TimelineDay, TimelineStop } from './types'

function stop(id: string, photos = 1, latitude: number | null = 37.0): TimelineStop {
  const coordinate = latitude === null ? null : { latitude, longitude: 127.0 }
  return {
    photos: Array.from({ length: photos }, (_, i) => ({ id: i === 0 ? id : `${id}-${i}`, takenAt: 0, coordinate })),
    center: coordinate,
  }
}

const day = (n: number, stops: TimelineStop[]): TimelineDay => ({ day: `2026-11-${String(14 + n).padStart(2, '0')}`, stops })

const outline = (days: TimelineDay[], maxStops = 40, thumbnailsPerStop = 4) =>
  makeShareOutline(days, { maxStops, thumbnailsPerStop, title: (s) => `이름-${stopId(s)}` })

const numbers = (o: ReturnType<typeof outline>) => o.sections.map((s) => s.stops.map((item) => item.number))

describe('makeShareOutline', () => {
  test('번호는 날짜를 넘어 이어진다', () => {
    const result = outline([day(0, [stop('a'), stop('b')]), day(1, [stop('c')])])
    expect(numbers(result)).toEqual([[1, 2], [3]])
    expect(result.sections.map((s) => s.day)).toEqual(['2026-11-14', '2026-11-15'])
    expect(result.hiddenStops).toBe(0)
  })

  test('한도를 넘는 머문 곳은 숨긴 수로 센다', () => {
    const result = outline([day(0, [stop('a'), stop('b')]), day(1, [stop('c'), stop('d')]), day(2, [stop('e')])], 3)
    expect(result.sections.map((s) => s.stops.map((item) => stopId(item.stop)))).toEqual([['a', 'b'], ['c']])
    expect(result.hiddenStops).toBe(2)
  })

  test('썸네일은 정한 수까지만, 나머지는 센다', () => {
    const [first, second] = outline([day(0, [stop('a', 6), stop('b', 2)])], 40, 4).sections[0].stops
    expect(first.thumbnailIDs).toEqual(['a', 'a-1', 'a-2', 'a-3'])
    expect(first.moreCount).toBe(2)
    expect(second.thumbnailIDs).toEqual(['b', 'b-1'])
    expect(second.moreCount).toBe(0)
  })

  test('사진 수에는 숨긴 머문 곳도 포함한다', () => {
    expect(outline([day(0, [stop('a', 3), stop('b', 5)])], 1).photoCount).toBe(8)
  })

  test('경로는 날짜별로 따로, 위치 없는 곳은 뺀다', () => {
    const result = outline([day(0, [stop('a', 1, 37.0), stop('b', 1, null), stop('c', 1, 37.1)]), day(1, [stop('d', 1, 37.2)])])
    expect(result.routes.map((route) => route.map((pin) => pin.number))).toEqual([[1, 3], [4]])
    expect(result.routes[0].map((pin) => pin.coordinate.latitude)).toEqual([37.0, 37.1])
  })

  test('제목은 만들 때 한 번만 묻는다', () => {
    const calls: string[] = []
    let prefix = '처음'
    const result = makeShareOutline([day(0, [stop('a'), stop('b')])], {
      maxStops: 40,
      thumbnailsPerStop: 4,
      title: (s) => {
        calls.push(stopId(s))
        return `${prefix}-${stopId(s)}`
      },
    })
    prefix = '나중'
    expect(calls).toEqual(['a', 'b'])
    expect(result.sections[0].stops.map((item) => item.title)).toEqual(['처음-a', '처음-b'])
  })

  test('날짜가 없으면 빈 내용', () => {
    const result = outline([])
    expect(result.sections).toEqual([])
    expect(result.routes).toEqual([])
    expect(result.photoCount).toBe(0)
  })
})

describe('retitled', () => {
  test('이름을 받은 머문 곳만 바꾼다', () => {
    const first = outline([day(0, [stop('a'), stop('b')]), day(1, [stop('c')])])
    const updated = retitled(first, (s) => (stopId(s) === 'b' ? '성수동' : null))
    expect(updated.sections.map((s) => s.stops.map((item) => item.title))).toEqual([['이름-a', '성수동'], ['이름-c']])
  })

  test('그 밖의 것은 그대로 둔다', () => {
    const first = outline([day(0, [stop('a', 6), stop('b', 1, null)]), day(1, [stop('c')])], 2)
    const updated = retitled(first, () => '새 이름')
    expect(numbers(updated)).toEqual(numbers(first))
    expect(updated.sections[0].stops[0].thumbnailIDs).toEqual(first.sections[0].stops[0].thumbnailIDs)
    expect(updated.routes).toEqual(first.routes)
    expect(updated.hiddenStops).toBe(1)
    expect(updated.photoCount).toBe(first.photoCount)
    // 원래 내용은 바뀌지 않는다.
    expect(first.sections[0].stops[0].title).toBe('이름-a')
  })
})
