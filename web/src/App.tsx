import { useEffect, useMemo, useRef, useState } from 'react'
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
import { filesFromDrop } from './services/droppedFiles'
import { downloadBlob, makeShareImage } from './services/shareImage'

export default function App() {
  const timeline = useTimeline()
  const [focus, setFocus] = useState<{ coordinate: Coordinate } | null>(null)
  const [isSharing, setIsSharing] = useState(false)
  const [shareError, setShareError] = useState(false)
  const mapColumn = useRef<HTMLDivElement>(null)

  /** 머문 곳을 누르면 지도를 그곳으로 옮긴다. */
  function focusOn(coordinate: Coordinate) {
    setFocus({ coordinate })
    // 좁은 화면에서는 지도가 목록 위에 있어 화면 밖일 수 있다. 지도가 보이게 올려 보낸다.
    const element = mapColumn.current
    if (element && element.getBoundingClientRect().top < 0) {
      element.scrollIntoView({ behavior: 'smooth', block: 'start' })
    }
  }

  const { days, stops, title, number, addFiles } = timeline

  // 올리는 영역 밖에 떨어뜨려도 받는다. 막지 않으면 브라우저가 그 사진 파일로 이동해 타임라인이 사라진다.
  useEffect(() => {
    // 페이지 안에서 끌기 시작한 것(지도 그림, 링크 등)은 밖에서 가져온 사진이 아니므로 받지 않는다.
    let fromThisPage = false
    const started = () => {
      fromThisPage = true
    }
    const ended = () => {
      fromThisPage = false
    }
    const allow = (event: DragEvent) => event.preventDefault()
    const drop = (event: DragEvent) => {
      event.preventDefault()
      if (fromThisPage) {
        fromThisPage = false
        return
      }
      // 폴더를 떨어뜨리면 그 안의 사진을 꺼낸다.
      void filesFromDrop(event.dataTransfer).then(addFiles)
    }
    window.addEventListener('dragstart', started)
    window.addEventListener('dragend', ended)
    window.addEventListener('dragover', allow)
    window.addEventListener('drop', drop)
    return () => {
      window.removeEventListener('dragstart', started)
      window.removeEventListener('dragend', ended)
      window.removeEventListener('dragover', allow)
      window.removeEventListener('drop', drop)
    }
  }, [addFiles])
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
        thumbnail: timeline.ensureThumbnail,
        lateName: timeline.latestName,
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

      <DropZone compact={hasPhotos} onFiles={(files) => void addFiles(files)} />

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
          <div className="map-column" ref={mapColumn}>
            {pins.length > 0 ? (
              <TimelineMap pins={pins} routes={routes} focus={focus} />
            ) : (
              <p className="notice">올린 사진에 위치 정보가 없어 지도를 표시하지 못해요.</p>
            )}
          </div>
          <StopList timeline={timeline} onFocus={focusOn} />
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
