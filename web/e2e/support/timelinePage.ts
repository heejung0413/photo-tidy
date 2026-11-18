import type { Download, Locator, Page } from '@playwright/test'
import { readFileSync } from 'node:fs'
import { basename } from 'node:path'

/** 타임라인 화면. 자주 찾는 요소와 조작을 한곳에 둔다. */
export class TimelinePage {
  readonly page: Page

  constructor(page: Page) {
    this.page = page
  }

  // ---- 요소 ----

  /** 머문 곳 카드 전체(화면 순서). */
  get cards(): Locator {
    return this.page.getByTestId('stop-card')
  }

  /** index번째 머문 곳 카드(0부터). */
  card(index: number): Locator {
    return this.cards.nth(index)
  }

  /** 머리말의 기간·장수. */
  get summary(): Locator {
    return this.page.getByTestId('summary')
  }

  get dayDividers(): Locator {
    return this.page.getByTestId('day-divider')
  }

  get map(): Locator {
    return this.page.getByTestId('map')
  }

  /** 지도의 번호 핀. */
  get pins(): Locator {
    return this.page.locator('.map-pin')
  }

  /** 그려진 썸네일. 그리지 못한 사진의 빈 칸은 들어가지 않는다. */
  get thumbnails(): Locator {
    return this.page.locator('img.thumbnail')
  }

  /** 사진이 없을 때의 안내. */
  get emptyMessage(): Locator {
    return this.page.getByText('사진을 여기에 끌어다 놓으세요')
  }

  /** "사진을 읽는 중…" 진행 표시. */
  get readingStatus(): Locator {
    return this.page.getByRole('status')
  }

  // ---- 조작 ----

  /** 파일 선택 창으로 고른 것처럼 올린다. */
  async upload(files: string[]): Promise<void> {
    await this.page.getByTestId('file-input').setInputFiles(files)
  }

  async clear(): Promise<void> {
    await this.page.getByRole('button', { name: '전부 지우기' }).click()
  }

  /** "이미지로 저장"을 눌러 내려받는다. path를 주면 그곳에 저장한다. */
  async saveImage(path?: string): Promise<Download> {
    const waiting = this.page.waitForEvent('download')
    await this.page.getByRole('button', { name: '이미지로 저장' }).click()
    const download = await waiting
    if (path) await download.saveAs(path)
    return download
  }

  /**
   * 밖에서 끌어온 파일 하나를 올리는 영역 밖(맨 아래 안내문)에 떨어뜨린다.
   * 페이지가 기본 동작(그 파일로 이동)을 막았는지 돌려준다.
   */
  async dropFile(path: string, name: string = basename(path)): Promise<boolean> {
    return this.page.evaluate(
      ({ base64, fileName }) => {
        const data = Uint8Array.from(atob(base64), (char) => char.charCodeAt(0))
        const transfer = new DataTransfer()
        transfer.items.add(new File([data], fileName, { type: 'image/jpeg' }))
        const event = new DragEvent('drop', { dataTransfer: transfer, bubbles: true, cancelable: true })
        document.querySelector('.footer')!.dispatchEvent(event)
        return event.defaultPrevented
      },
      { base64: readFileSync(path).toString('base64'), fileName: name },
    )
  }

  /** 페이지 안의 첫 썸네일을 끌어서 페이지에 놓는다(끌려 가는 내용은 path의 사진). */
  async dragThumbnailOntoPage(path: string): Promise<void> {
    await this.page.evaluate((base64) => {
      const data = Uint8Array.from(atob(base64), (char) => char.charCodeAt(0))
      const transfer = new DataTransfer()
      transfer.items.add(new File([data], 'dragged-thumbnail.jpg', { type: 'image/jpeg' }))
      const thumbnail = document.querySelector('img.thumbnail')!
      thumbnail.dispatchEvent(new DragEvent('dragstart', { dataTransfer: transfer, bubbles: true }))
      document
        .querySelector('.footer')!
        .dispatchEvent(new DragEvent('drop', { dataTransfer: transfer, bubbles: true, cancelable: true }))
      thumbnail.dispatchEvent(new DragEvent('dragend', { bubbles: true }))
    }, readFileSync(path).toString('base64'))
  }

  /** Finder에서 폴더를 끌어다 놓는 것과 같은 이벤트를 보낸다. */
  async dropFolder(directory: string): Promise<void> {
    const cdp = await this.page.context().newCDPSession(this.page)
    const data = { items: [], files: [directory], dragOperationsMask: 1 }
    for (const type of ['dragEnter', 'dragOver', 'drop'] as const) {
      await cdp.send('Input.dispatchDragEvent', { type, x: 400, y: 300, data })
    }
  }

  /** 지도에서 1번 핀과 2번 핀 사이의 화면 거리. 지도를 확대하면 커진다. */
  async pinSpacing(): Promise<number> {
    const first = await this.pins.nth(0).boundingBox()
    const second = await this.pins.nth(1).boundingBox()
    return Math.hypot(first!.x - second!.x, first!.y - second!.y)
  }
}
