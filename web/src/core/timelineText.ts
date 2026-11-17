import { localTimeZone, stopEnd, stopStart } from './timeline'
import type { TimelineStop } from './types'

/** "오전 9:10" 또는 "오전 9:10–오전 11:20". 시작과 끝 표시가 같으면 하나만 적는다. */
export function timeRange(stop: TimelineStop, locale?: string, timeZone: string = localTimeZone()): string {
  const formatter = new Intl.DateTimeFormat(locale, { hour: 'numeric', minute: '2-digit', timeZone })
  const start = formatter.format(stopStart(stop))
  const end = formatter.format(stopEnd(stop))
  return start === end ? start : `${start}–${end}`
}

/** "2026-11-14" → 그 날짜의 UTC 자정. 날짜 글자를 만들 때만 쓴다. */
function dayToUTC(day: string): number {
  const [year, month, date] = day.split('-').map(Number)
  return Date.UTC(year, month - 1, date)
}

/** 기간. 하루뿐이면 날짜 하나, 아니면 "첫날 – 마지막 날". */
export function period(firstDay: string, lastDay: string, locale?: string): string {
  const formatter = new Intl.DateTimeFormat(locale, { year: 'numeric', month: 'long', day: 'numeric', timeZone: 'UTC' })
  const first = formatter.format(dayToUTC(firstDay))
  return firstDay === lastDay ? first : `${first} – ${formatter.format(dayToUTC(lastDay))}`
}

/** 날짜 구분 줄 글자. "11월 14일 (토)". 여러 해에 걸치면 withYear로 연도를 붙인다. */
export function dayLabel(day: string, locale?: string, withYear = false): string {
  return new Intl.DateTimeFormat(locale, {
    year: withYear ? 'numeric' : undefined,
    month: 'long',
    day: 'numeric',
    weekday: 'short',
    timeZone: 'UTC',
  }).format(dayToUTC(day))
}
