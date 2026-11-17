import { useMemo, useState } from 'react'
import './App.css'
import { DropZone } from './components/DropZone'
import { StopList } from './components/StopList'
import { TimelineMap, type MapPin } from './components/TimelineMap'
import { useTimeline } from './components/useTimeline'
import { makeShareOutline } from './core/shareOutline'
import { dayRoute, stopId } from './core/timeline'
import { period } from './core/timelineText'
import { Tuning } from './core/tuning'
import type { Coordinate } from './core/types'
import { downloadBlob, makeShareImage } from './services/shareImage'

export default function App() {
  const timeline = useTimeline()
  const [focus, setFocus] = useState<{ coordinate: Coordinate } | null>(null)
  const [isSharing, setIsSharing] = useState(false)
  const [shareError, setShareError] = useState(false)

  const { days, stops, title, number } = timeline
  const hasPhotos = timeline.photoCount > 0

  const pins = useMemo<MapPin[]>(
    () =>
      stops.flatMap((stop) =>
        stop.center ? [{ id: stopId(stop), number: number(stop), title: title(stop), coordinate: stop.center }] : [],
      ),
    [stops, number, title],
  )
  const routes = useMemo(() => days.map(dayRoute), [days])

  const summary = hasPhotos ? `${period(days[0].day, days[days.length - 1].day)} · ${timeline.photoCount}장` : ''

  async function share() {
    // 누른 순간의 내용을 고정한다. 만드는 동안 사진을 더 올려도 섞이지 않는다.
    const outline = makeShareOutline(days, {
      maxStops: Tuning.shareMaxStops,
      thumbnailsPerStop: Tuning.shareThumbnails,
      title,
    })
    setIsSharing(true)
    setShareError(false)
    try {
      const blob = await makeShareImage({
        outline,
        title: '타임라인',
        subtitle: summary,
        thumbnail: timeline.thumbnail,
        lateName: timeline.knownName,
      })
      downloadBlob(blob, '타임라인.png')
    } catch {
      setShareError(true)
    } finally {
      setIsSharing(false)
    }
  }

  return (
    <div className="page">
      <header className="header">
        <div>
          <h1>Photo Tidy 타임라인</h1>
          {hasPhotos && (
            <p className="summary" data-testid="summary">
              {summary}
            </p>
          )}
        </div>
        {hasPhotos && (
          <div className="actions">
            <button type="button" className="button primary" onClick={share} disabled={isSharing}>
              {isSharing ? '이미지 만드는 중…' : '이미지로 저장'}
            </button>
            <button
              type="button"
              className="button"
              onClick={() => {
                timeline.clear()
                setFocus(null)
              }}
            >
              전부 지우기
            </button>
          </div>
        )}
      </header>

      <DropZone compact={hasPhotos} onFiles={(files) => void timeline.addFiles(files)} />

      {timeline.reading && (
        <p className="notice" role="status">
          사진을 읽는 중… {timeline.reading.done} / {timeline.reading.total}
        </p>
      )}
      {timeline.skippedFiles > 0 && <p className="notice">읽지 못한 파일 {timeline.skippedFiles}개 (사진이 아닌 파일)</p>}
      {timeline.fileTimePhotos > 0 && (
        <p className="notice">촬영 시각이 없어 파일 시각을 쓴 사진 {timeline.fileTimePhotos}장</p>
      )}
      {shareError && <p className="notice error">이미지를 만들지 못했어요. 다시 시도해 주세요.</p>}

      {hasPhotos && (
        <div className="content">
          <div className="map-column">
            {pins.length > 0 ? (
              <TimelineMap pins={pins} routes={routes} focus={focus} />
            ) : (
              <p className="notice">올린 사진에 위치 정보가 없어 지도를 표시하지 못해요.</p>
            )}
          </div>
          <StopList timeline={timeline} onFocus={(coordinate) => setFocus({ coordinate })} />
        </div>
      )}

      <footer className="footer">
        <p>사진은 이 브라우저 밖으로 나가지 않습니다.</p>
        <p>장소 이름을 받을 때 머문 곳의 좌표가, 지도를 그릴 때 보고 있는 지역이 오픈스트리트맵 서버로 전송됩니다.</p>
        <p>
          지도 ©{' '}
          <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noreferrer">
            OpenStreetMap
          </a>{' '}
          기여자
        </p>
      </footer>
    </div>
  )
}
