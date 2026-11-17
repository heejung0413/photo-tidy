import { stopId } from '../core/timeline'
import { dayLabel } from '../core/timelineText'
import type { Coordinate, TimelineStop } from '../core/types'
import { StopCard } from './StopCard'
import type { Timeline } from './useTimeline'

interface Props {
  timeline: Timeline
  onFocus: (coordinate: Coordinate) => void
}

/** 날짜 구분 줄과 그날의 머문 곳들. */
export function StopList({ timeline, onFocus }: Props) {
  // 여러 해에 걸치면 날짜 구분 줄에 연도도 적는다.
  const withYear = new Set(timeline.days.map((day) => day.day.slice(0, 4))).size > 1

  return (
    <div className="stop-list">
      {timeline.days.map((day) => (
        <section key={day.day}>
          <h2 className="day-divider" data-testid="day-divider">
            {dayLabel(day.day, undefined, withYear)}
          </h2>
          {day.stops.map((stop: TimelineStop) => (
            <StopCard
              key={stopId(stop)}
              stop={stop}
              number={timeline.number(stop)}
              title={timeline.title(stop)}
              customName={timeline.customName(stop)}
              thumbnail={timeline.thumbnail}
              onFocus={() => stop.center && onFocus(stop.center)}
              onRename={(text) => timeline.rename(stop, text)}
            />
          ))}
        </section>
      ))}
    </div>
  )
}
