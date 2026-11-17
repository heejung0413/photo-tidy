import { useRef, useState } from 'react'

interface Props {
  /** 사진이 이미 있으면 작게 그린다. */
  compact: boolean
  onFiles: (files: File[]) => void
}

/**
 * 사진을 끌어다 놓거나 파일 선택 창에서 고르는 영역.
 * 떨어뜨린 파일은 페이지 전체가 받는다(App). 여기서는 끌고 있을 때 강조만 한다.
 */
export function DropZone({ compact, onFiles }: Props) {
  const input = useRef<HTMLInputElement>(null)
  const [isOver, setIsOver] = useState(false)

  return (
    <div
      className={`drop-zone${compact ? ' compact' : ''}${isOver ? ' over' : ''}`}
      onDragOver={(event) => {
        event.preventDefault()
        setIsOver(true)
      }}
      onDragLeave={() => setIsOver(false)}
      onDrop={() => setIsOver(false)}
    >
      {!compact && (
        <>
          <p className="drop-title">사진을 여기에 끌어다 놓으세요</p>
          <p className="drop-hint">위치와 촬영 시각이 든 사진으로 지도와 타임라인을 만듭니다.</p>
        </>
      )}
      <button type="button" className={compact ? 'button' : 'button primary'} onClick={() => input.current?.click()}>
        {compact ? '사진 더 올리기' : '사진 선택'}
      </button>
      <input
        ref={input}
        type="file"
        accept="image/*,.heic,.heif"
        multiple
        hidden
        data-testid="file-input"
        onChange={(event) => {
          onFiles([...(event.target.files ?? [])])
          event.target.value = ''
        }}
      />
    </div>
  )
}
