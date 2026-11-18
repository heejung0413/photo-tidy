import type { Page } from '@playwright/test'

// 브라우저 기능을 감싸 상황을 만들거나 기록한다.
// 감싸는 코드는 페이지를 열 때 들어가야 하므로, 설치한 뒤 페이지를 다시 연다(올린 사진은 사라진다).

type Recorded = { drawnTexts?: string[]; downloadHref?: string }

/** 썸네일 만들기를 느리게 한다(사진 한 장에 ms). 큰 사진이 많을 때의 상황을 흉내 낸다. */
export async function slowThumbnails(page: Page, ms: number): Promise<void> {
  await page.addInitScript((delay) => {
    const original = window.createImageBitmap.bind(window)
    window.createImageBitmap = (async (...args: Parameters<typeof createImageBitmap>) => {
      await new Promise((resolve) => setTimeout(resolve, delay))
      return original(...args)
    }) as typeof createImageBitmap
  }, ms)
  await page.reload()
}

/** 캔버스에 쓰는 글자를 기록하기 시작한다. 공유 이미지에 어떤 글자가 들어갔는지 볼 때 쓴다. */
export async function recordCanvasText(page: Page): Promise<void> {
  await page.addInitScript(() => {
    const texts: string[] = []
    ;(window as unknown as Recorded).drawnTexts = texts
    const original = CanvasRenderingContext2D.prototype.fillText
    CanvasRenderingContext2D.prototype.fillText = function (text: string, ...rest: [number, number, number?]) {
      texts.push(text)
      return original.call(this, text, ...rest)
    }
  })
  await page.reload()
}

/** recordCanvasText 뒤로 캔버스에 쓴 글자 전부. */
export function drawnTexts(page: Page): Promise<string[]> {
  return page.evaluate(() => (window as unknown as Recorded).drawnTexts ?? [])
}

/** 내려받기 링크의 주소를 기록하기 시작한다. */
export async function recordDownloadHref(page: Page): Promise<void> {
  await page.addInitScript(() => {
    const original = HTMLAnchorElement.prototype.click
    HTMLAnchorElement.prototype.click = function () {
      if (this.download) (window as unknown as Recorded).downloadHref = this.href
      return original.call(this)
    }
  })
  await page.reload()
}

/** 기록해 둔 내려받기 주소에서 아직 내용을 읽을 수 있는가. */
export function downloadStillAlive(page: Page): Promise<boolean> {
  return page.evaluate(async () => {
    try {
      const response = await fetch((window as unknown as Recorded).downloadHref!)
      return (await response.blob()).size > 1000
    } catch {
      return false
    }
  })
}
