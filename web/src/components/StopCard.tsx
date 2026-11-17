import { useState } from 'react'
import { timeRange } from '../core/timelineText'
import type { TimelineStop } from '../core/types'

interface Props {
  stop: TimelineStop
  number: number
  title: string
  /** 직접 붙인 이름. 이름 고치기 칸의 처음 값. */
  customName: string | null
  thumbnail: (photoId: string) => string | undefined
  onFocus: () => void
  onRename: (text: string) => void
}

function Thumbnail({ src }: { src: string | undefined }) {
  const [failed, setFailed] = useState(false)
  if (!src || failed) {
    // 브라우저가 그리지 못하는 형식(HEIC 등).
    return <div className="thumbnail empty" role="img" aria-label="미리 볼 수 없는 사진" />
  }
  return <img className="thumbnail" src={src} alt="" loading="lazy" decoding="async" onError={() => setFailed(true)} />
}

export function StopCard({ stop, number, title, customName, thumbnail, onFocus, onRename }: Props) {
  const [editing, setEditing] = useState(false)
  const [text, setText] = useState('')

  return (
    <article className="card stop-card" data-testid="stop-card">
      <div className="stop-head">
        <button type="button" className="stop-main" onClick={onFocus} disabled={!stop.center}>
          <span className="badge">{number}</span>
          <span className="stop-text">
            <span className="stop-title">{title}</span>
            <span className="stop-meta">
              {timeRange(stop)} · {stop.photos.length}장
            </span>
          </span>
        </button>
        <button
          type="button"
          className="icon-button"
          aria-label="장소 이름 바꾸기"
          onClick={() => {
            setText(customName ?? '')
            setEditing(true)
          }}
        >
          ✎
        </button>
      </div>

      {editing && (
        <form
          className="rename"
          onSubmit={(event) => {
            event.preventDefault()
            onRename(text)
            setEditing(false)
          }}
        >
          <input
            autoFocus
            aria-label="장소 이름"
            placeholder="이름"
            value={text}
            onChange={(event) => setText(event.target.value)}
          />
          <button type="submit" className="button primary">
            저장
          </button>
          <button type="button" className="button" onClick={() => setEditing(false)}>
            취소
          </button>
          <p className="rename-hint">비워 두고 저장하면 자동으로 찾은 이름으로 돌아가요.</p>
        </form>
      )}

      <div className="thumbnails">
        {stop.photos.map((photo) => (
          <Thumbnail key={photo.id} src={thumbnail(photo.id)} />
        ))}
      </div>
    </article>
  )
}
