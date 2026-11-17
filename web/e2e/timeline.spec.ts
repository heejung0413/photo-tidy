import { expect, test, type Page } from '@playwright/test'
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

const fixtures = join(import.meta.dirname, 'fixtures')
const samples = ['t1-seongsu', 't2-forest', 't3-forest', 't4-namsan', 't5-gangnam', 't6-jamsil'].map((name) =>
  join(fixtures, `${name}.jpg`),
)

/** 1×1 투명 PNG. 지도 타일 대신 준다. */
const blankTile = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  'base64',
)

/** 지도 타일 응답을 늦출 시간(밀리초). 테스트가 바꾼다. */
let tileDelay = 0
/** 장소 이름 요청이 온 시각. */
let nameRequests: number[] = []

/** 바깥 서비스(지도 타일, 장소 이름)를 가짜 응답으로 바꾼다. */
async function stubServices(page: Page) {
  tileDelay = 0
  nameRequests = []
  await page.route('https://tile.openstreetmap.org/**', async (route) => {
    if (tileDelay > 0) await new Promise((resolve) => setTimeout(resolve, tileDelay))
    await route.fulfill({ contentType: 'image/png', body: blankTile, headers: { 'access-control-allow-origin': '*' } })
  })
  await page.route('https://nominatim.openstreetmap.org/**', (route) => {
    const url = new URL(route.request().url())
    nameRequests.push(Date.now())
    const latitude = Number(url.searchParams.get('lat'))
    // 남산 근처만 이름을 주고, 나머지는 이름 없는 응답을 준다.
    const address = Math.abs(latitude - 37.5512) < 0.001 ? { suburb: '가짜 남산동' } : {}
    return route.fulfill({ json: { address }, headers: { 'access-control-allow-origin': '*' } })
  })
}

/** 샘플을 이름만 바꿔 count개로 늘린다(이름이 다르면 다른 사진으로 본다). 읽는 데 시간이 걸리게 하려는 것. */
function manyCopies(directory: string, count: number): string[] {
  mkdirSync(directory, { recursive: true })
  return Array.from({ length: count }, (_, index) => {
    const path = join(directory, `copy-${index}.jpg`)
    copyFileSync(samples[index % samples.length], path)
    return path
  })
}

async function upload(page: Page, files: string[]) {
  await page.getByTestId('file-input').setInputFiles(files)
}

test.beforeEach(async ({ page }) => {
  await stubServices(page)
  await page.goto('/')
})

test('샘플 사진을 올리면 날짜별 머문 곳이 나온다', async ({ page }) => {
  await expect(page.getByText('사진을 여기에 끌어다 놓으세요')).toBeVisible()
  await upload(page, samples)

  await expect(page.getByTestId('day-divider')).toHaveCount(2)
  await expect(page.getByTestId('day-divider').nth(0)).toContainText('11월 14일')
  await expect(page.getByTestId('day-divider').nth(1)).toContainText('11월 15일')
  // 첫날 3곳(서울숲 2장은 한 곳), 둘째 날 2곳.
  await expect(page.getByTestId('stop-card')).toHaveCount(5)
  await expect(page.getByTestId('summary')).toContainText('6장')
  await expect(page.getByTestId('summary')).toContainText('2026년 11월 14일')
  await expect(page.getByTestId('stop-card').nth(1)).toContainText('2장')
  await expect(page.getByTestId('stop-card').nth(0)).toContainText('오전 9:10')
  await expect(page.getByTestId('stop-card').nth(1)).toContainText('오전 11:05–오전 11:20')

  // 지도에 번호 핀 5개.
  await expect(page.locator('.map-pin')).toHaveCount(5)
  await expect(page.locator('.map-pin').nth(4)).toHaveText('5')
  await page.screenshot({ path: 'test-results/shots/1-timeline.png', fullPage: true })
})

test('받아 온 장소 이름을 보여 주고, 못 받은 곳은 번호 이름으로 둔다', async ({ page }) => {
  await upload(page, samples)
  // 이름은 약 1초에 하나씩 받는다. 남산은 세 번째 머문 곳이다.
  await expect(page.getByTestId('stop-card').nth(2)).toContainText('가짜 남산동', { timeout: 15_000 })
  await expect(page.getByTestId('stop-card').nth(0)).toContainText('장소 1')
})

test('같은 사진을 다시 올려도 한 번만 들어간다', async ({ page }) => {
  await upload(page, samples.slice(0, 3))
  await expect(page.getByTestId('summary')).toContainText('3장')
  await upload(page, samples)
  await expect(page.getByTestId('summary')).toContainText('6장')
  await expect(page.getByTestId('stop-card')).toHaveCount(5)
})

test('장소 이름을 고치면 바뀌고, 다시 방문해도 남는다', async ({ page }) => {
  await upload(page, samples)
  const first = page.getByTestId('stop-card').nth(0)
  await first.getByRole('button', { name: '장소 이름 바꾸기' }).click()
  await first.getByRole('textbox', { name: '장소 이름' }).fill('우리 카페')
  await first.getByRole('button', { name: '저장' }).click()
  await expect(first).toContainText('우리 카페')
  // 옆 장소는 그대로다.
  await expect(page.getByTestId('stop-card').nth(1)).not.toContainText('우리 카페')

  await page.reload()
  await upload(page, samples)
  await expect(page.getByTestId('stop-card').nth(0)).toContainText('우리 카페')

  // 비워서 저장하면 자동 이름으로 돌아간다.
  const again = page.getByTestId('stop-card').nth(0)
  await again.getByRole('button', { name: '장소 이름 바꾸기' }).click()
  await expect(again.getByRole('textbox', { name: '장소 이름' })).toHaveValue('우리 카페')
  await again.getByRole('textbox', { name: '장소 이름' }).fill('')
  await again.getByRole('button', { name: '저장' }).click()
  await expect(again).toContainText('장소 1')
})

test('썸네일은 원본이 아니라 작게 줄인 그림이다', async ({ page }) => {
  await upload(page, samples)
  await expect(page.locator('img.thumbnail')).toHaveCount(6)
  const sizes = await page.locator('img.thumbnail').evaluateAll((images) =>
    images.map((image) => {
      const { naturalWidth, naturalHeight } = image as HTMLImageElement
      return Math.min(naturalWidth, naturalHeight)
    }),
  )
  // 샘플 원본은 1200×900. 짧은 변을 264로 줄인다.
  expect(sizes).toEqual([264, 264, 264, 264, 264, 264])
})

test('저장한 이미지에 지도의 핀·선과 사진이 그려져 있다', async ({ page }, testInfo) => {
  await upload(page, samples)
  await expect(page.locator('img.thumbnail')).toHaveCount(6)
  const download = page.waitForEvent('download')
  await page.getByRole('button', { name: '이미지로 저장' }).click()
  const path = testInfo.outputPath('content.png')
  await (await download).saveAs(path)

  const result = await page.evaluate(async (url) => {
    const image = new Image()
    image.src = url
    await image.decode()
    const canvas = document.createElement('canvas')
    canvas.width = image.naturalWidth
    canvas.height = image.naturalHeight
    const context = canvas.getContext('2d')!
    context.drawImage(image, 0, 0)
    const pixel = (x: number, y: number) => [...context.getImageData(x, y, 1, 1).data.slice(0, 3)]
    // 지도 영역(위쪽 여백 48 + 머리말 110부터 높이 560)에서 강조색 픽셀을 센다.
    const map = context.getImageData(48, 158, 984, 560).data
    let accent = 0
    for (let i = 0; i < map.length; i += 4) {
      if (Math.abs(map[i] - 13) < 12 && Math.abs(map[i + 1] - 133) < 12 && Math.abs(map[i + 2] - 122) < 12) accent += 1
    }
    // 첫 머문 곳(주황 사진)과 두 번째 머문 곳(초록 사진 2장)의 썸네일 가운데.
    return { accent, first: pixel(142, 984), second: pixel(142, 984 + 252), secondNext: pixel(142 + 144, 984 + 252) }
  }, `data:image/png;base64,${readFileSync(path).toString('base64')}`)

  // 핀 5개와 경로 선 3개.
  expect(result.accent).toBeGreaterThan(3000)
  const [r1, g1, b1] = result.first
  expect(r1).toBeGreaterThan(200)
  expect(g1).toBeGreaterThan(100)
  expect(g1).toBeLessThan(180)
  expect(b1).toBeLessThan(100)
  for (const [r, g, b] of [result.second, result.secondNext]) {
    expect(g).toBeGreaterThan(r + 50)
    expect(g).toBeGreaterThan(b + 50)
  }
})

test('이미지로 저장하면 PNG를 내려받는다', async ({ page }, testInfo) => {
  await upload(page, samples)
  await expect(page.getByTestId('stop-card')).toHaveCount(5)
  const download = page.waitForEvent('download')
  await page.getByRole('button', { name: '이미지로 저장' }).click()
  const file = await download
  expect(file.suggestedFilename()).toBe('타임라인.png')
  const path = testInfo.outputPath('shared.png')
  await file.saveAs(path)

  // PNG이고, 너비 1080에 머문 곳 5곳이 들어갈 만큼 길다.
  const size = await page.evaluate(async (url) => {
    const image = new Image()
    image.src = url
    await image.decode()
    return { width: image.naturalWidth, height: image.naturalHeight }
  }, `data:image/png;base64,${(await import('node:fs')).readFileSync(path).toString('base64')}`)
  expect(size.width).toBe(1080)
  expect(size.height).toBeGreaterThan(1500)
  ;(await import('node:fs')).copyFileSync(path, 'test-results/shots/2-shared.png')
})

test('사진이 아닌 파일은 건너뛰고 알린다', async ({ page }) => {
  await upload(page, [join(fixtures, '..', 'timeline.spec.ts'), samples[0]])
  await expect(page.getByText('읽지 못한 파일 1개')).toBeVisible()
  await expect(page.getByTestId('summary')).toContainText('1장')
})

test('전부 지우면 처음 화면으로 돌아간다', async ({ page }) => {
  await upload(page, samples)
  await expect(page.getByTestId('stop-card')).toHaveCount(5)
  await page.getByRole('button', { name: '전부 지우기' }).click()
  await expect(page.getByTestId('stop-card')).toHaveCount(0)
  await expect(page.getByText('사진을 여기에 끌어다 놓으세요')).toBeVisible()
})

test('장소 이름은 머문 곳마다 한 번씩, 1초 넘게 띄워서 묻는다', async ({ page }) => {
  await upload(page, samples)
  await expect(page.getByTestId('stop-card')).toHaveCount(5)
  await expect.poll(() => nameRequests.length, { timeout: 15_000 }).toBe(5)
  // 더 기다려도 다시 묻지 않는다.
  await page.waitForTimeout(2500)
  expect(nameRequests).toHaveLength(5)
  const gaps = nameRequests.slice(1).map((time, index) => time - nameRequests[index])
  expect(Math.min(...gaps)).toBeGreaterThanOrEqual(1000)
})

test('읽는 도중 전부 지우면, 읽던 사진이 되살아나지 않는다', async ({ page }, testInfo) => {
  await upload(page, samples)
  await expect(page.getByTestId('stop-card')).toHaveCount(5)
  await upload(page, manyCopies(testInfo.outputPath('copies'), 400))
  await expect(page.getByRole('status')).toContainText('사진을 읽는 중')
  await page.getByRole('button', { name: '전부 지우기' }).click()

  await expect(page.getByText('사진을 여기에 끌어다 놓으세요')).toBeVisible()
  await expect(page.getByRole('status')).toHaveCount(0)
  // 읽기가 끝날 만큼 기다려도 처음 화면 그대로다.
  await page.waitForTimeout(3000)
  await expect(page.getByTestId('stop-card')).toHaveCount(0)
  await expect(page.getByText('사진을 여기에 끌어다 놓으세요')).toBeVisible()

  // 지운 뒤 다시 올리면 정상으로 들어간다.
  await upload(page, samples)
  await expect(page.getByTestId('summary')).toContainText('6장')
})

test('이미지를 만드는 사이 도착한 장소 이름이 이미지에 들어간다', async ({ page }) => {
  // 캔버스에 쓴 글자를 기록한다.
  await page.addInitScript(() => {
    const texts: string[] = []
    ;(window as unknown as { drawnTexts: string[] }).drawnTexts = texts
    const original = CanvasRenderingContext2D.prototype.fillText
    CanvasRenderingContext2D.prototype.fillText = function (text: string, ...rest: [number, number, number?]) {
      texts.push(text)
      return original.call(this, text, ...rest)
    }
  })
  await page.reload()
  tileDelay = 4000
  await upload(page, samples)
  await expect(page.getByTestId('stop-card')).toHaveCount(5)
  // 남산(세 번째)의 이름은 약 2초 뒤에 온다. 그 전에 저장을 누른다.
  await expect(page.getByTestId('stop-card').nth(2)).toContainText('장소 3')
  const download = page.waitForEvent('download')
  await page.getByRole('button', { name: '이미지로 저장' }).click()
  await download

  const texts = await page.evaluate(() => (window as unknown as { drawnTexts: string[] }).drawnTexts)
  expect(texts).toContain('가짜 남산동')
  expect(texts).not.toContain('장소 3')
  // 이름을 못 받은 곳은 누른 순간의 이름 그대로다.
  expect(texts).toContain('장소 1')
})

test('올리는 영역 밖에 떨어뜨려도 사진을 받는다', async ({ page }) => {
  await upload(page, samples.slice(0, 1))
  await expect(page.getByTestId('summary')).toContainText('1장')
  const bytes = readFileSync(samples[5]).toString('base64')
  const prevented = await page.evaluate((base64) => {
    const data = Uint8Array.from(atob(base64), (char) => char.charCodeAt(0))
    const transfer = new DataTransfer()
    transfer.items.add(new File([data], 't6-jamsil.jpg', { type: 'image/jpeg' }))
    const event = new DragEvent('drop', { dataTransfer: transfer, bubbles: true, cancelable: true })
    document.querySelector('.footer')!.dispatchEvent(event)
    return event.defaultPrevented
  }, bytes)
  // 막지 않으면 브라우저가 그 사진 파일로 이동해 타임라인이 사라진다.
  expect(prevented).toBe(true)
  await expect(page.getByTestId('summary')).toContainText('2장')
})

test('읽지 못한 파일 안내는 다음에 올릴 때 지워진다', async ({ page }) => {
  await upload(page, [join(fixtures, '..', 'timeline.spec.ts')])
  await expect(page.getByText('읽지 못한 파일 1개')).toBeVisible()
  await upload(page, samples)
  await expect(page.getByTestId('summary')).toContainText('6장')
  await expect(page.getByText('읽지 못한 파일')).toHaveCount(0)
})

test('사진이 든 폴더를 통째로 떨어뜨리면 그 안의 사진을 받는다', async ({ page }, testInfo) => {
  // 폴더 안에 날짜별 폴더, 메모 파일, 숨김 파일이 섞여 있다.
  const trip = testInfo.outputPath('trip')
  mkdirSync(join(trip, 'day1'), { recursive: true })
  mkdirSync(join(trip, 'day2'), { recursive: true })
  samples.slice(0, 4).forEach((path, index) => copyFileSync(path, join(trip, 'day1', `a${index}.jpg`)))
  samples.slice(4).forEach((path, index) => copyFileSync(path, join(trip, 'day2', `b${index}.jpg`)))
  writeFileSync(join(trip, 'notes.txt'), '메모')
  writeFileSync(join(trip, '.DS_Store'), '')

  // 실제로 Finder에서 폴더를 끌어다 놓는 것과 같은 이벤트를 보낸다.
  const cdp = await page.context().newCDPSession(page)
  const data = { items: [], files: [trip], dragOperationsMask: 1 }
  for (const type of ['dragEnter', 'dragOver', 'drop'] as const) {
    await cdp.send('Input.dispatchDragEvent', { type, x: 400, y: 300, data })
  }

  await expect(page.getByTestId('summary')).toContainText('6장')
  await expect(page.getByTestId('stop-card')).toHaveCount(5)
  // 메모 파일만 읽지 못한 파일로 센다. 숨김 파일과 폴더 자체는 세지 않는다.
  await expect(page.getByText('읽지 못한 파일 1개')).toBeVisible()
})
