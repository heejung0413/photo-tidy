import { describe, expect, test } from 'vitest'
import { placeKey } from './placeKey'
import { dayLabel, period, timeRange } from './timelineText'
import type { TimelineStop } from './types'

const REF = Date.UTC(2001, 0, 1)
const at = (hour: number, minute: number) => REF + (hour * 3600 + minute * 60) * 1000

function stop(times: number[]): TimelineStop {
  return { photos: times.map((takenAt, i) => ({ id: `p${i}`, takenAt, coordinate: null })), center: null }
}

describe('timeRange', () => {
  test('사진이 하나면 시각 하나', () => {
    const text = timeRange(stop([at(9, 10)]), 'en-US', 'UTC')
    expect(text.startsWith('9:10')).toBe(true)
    expect(text).not.toContain('–')
  })

  test('같은 분에 찍은 사진들도 시각 하나', () => {
    expect(timeRange(stop([at(9, 10), at(9, 10) + 40_000]), 'en-US', 'UTC')).not.toContain('–')
  })

  test('시작과 끝을 잇는다', () => {
    const text = timeRange(stop([at(11, 5), at(11, 12), at(15, 20)]), 'en-US', 'UTC')
    const parts = text.split('–')
    expect(parts).toHaveLength(2)
    expect(parts[0].startsWith('11:05')).toBe(true)
    expect(parts[1].startsWith('3:20')).toBe(true)
  })

  test('언어와 시간대를 따른다', () => {
    const text = timeRange(stop([at(0, 10)]), 'ko-KR', 'Asia/Seoul')
    expect(text).toContain('오전')
    expect(text).toContain('9:10')
  })
})

describe('period', () => {
  test('하루뿐이면 날짜 하나', () => {
    const text = period('2001-01-01', '2001-01-01', 'en-US')
    expect(text).toContain('2001')
    expect(text).not.toContain('–')
  })

  test('여러 날이면 첫날과 마지막 날', () => {
    const parts = period('2001-01-01', '2002-02-05', 'ko-KR').split(' – ')
    expect(parts).toHaveLength(2)
    expect(parts[0]).toContain('2001')
    expect(parts[1]).toContain('2002')
  })
})

describe('dayLabel', () => {
  test('월, 일, 요일', () => {
    const text = dayLabel('2026-11-14', 'ko-KR')
    expect(text).toContain('11월 14일')
    expect(text).toContain('토')
    expect(text).not.toContain('2026')
  })

  test('연도를 붙일 수 있다', () => {
    expect(dayLabel('2026-11-14', 'ko-KR', true)).toContain('2026')
  })
})

describe('placeKey', () => {
  test('소수 셋째 자리로 반올림한다', () => {
    expect(placeKey({ latitude: 37.54464, longitude: 127.05587 })).toBe('37.545,127.056')
    expect(placeKey({ latitude: -33.8, longitude: 151.2 })).toBe('-33.800,151.200')
  })
})
