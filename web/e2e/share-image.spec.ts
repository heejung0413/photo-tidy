import { copyFileSync, mkdirSync } from 'node:fs'
import { downloadStillAlive, drawnTexts, recordCanvasText, recordDownloadHref, slowThumbnails } from './support/browserHooks.ts'
import { inspectPNG } from './support/image.ts'
import { samples, withDay } from './support/samples.ts'
import { expect, test } from './support/test.ts'

// "이미지로 저장": 타임라인을 PNG 한 장으로 만들어 내려받는다.
//
// 이미지 안의 자리(픽셀): 너비 1080, 바깥 여백 48. 지도는 (48, 158)부터 984×560.
// 첫 머문 곳의 첫 썸네일 가운데는 (142, 984)이고, 머문 곳 한 줄의 높이는 268, 썸네일 간격은 144다.
// 날짜 구분 줄(64)이 날짜마다 한 번 들어간다. 지도가 빠지면 이미지가 592(지도 560 + 간격 32)만큼 짧아진다.
const FIRST_THUMBNAIL = { x: 142, y: 984 }
const ROW = 268
const DAY_DIVIDER = 64
const MAP_BLOCK = 592

test('이미지로 저장하면 PNG를 내려받는다', async ({ page, timeline }, testInfo) => {
  await timeline.upload(samples)
  await expect(timeline.cards).toHaveCount(5)
  const path = testInfo.outputPath('shared.png')
  const file = await timeline.saveImage(path)
  expect(file.suggestedFilename()).toBe('타임라인.png')

  // PNG이고, 너비 1080에 머문 곳 5곳이 들어갈 만큼 길다.
  const size = await inspectPNG(page, path)
  expect(size.width).toBe(1080)
  expect(size.height).toBeGreaterThan(1500)
  mkdirSync('test-results/shots', { recursive: true })
  copyFileSync(path, 'test-results/shots/2-shared.png')
})

test('저장한 이미지에 지도의 핀·선과 사진이 그려져 있다', async ({ page, timeline }, testInfo) => {
  await timeline.upload(samples)
  await expect(timeline.thumbnails).toHaveCount(6)
  const path = testInfo.outputPath('content.png')
  await timeline.saveImage(path)

  const { x, y } = FIRST_THUMBNAIL
  const result = await inspectPNG(page, path, {
    // 지도 영역에서 강조색 픽셀을 센다.
    region: { x: 48, y: 158, width: 984, height: 560, color: [13, 133, 122], tolerance: 12 },
    // 첫 머문 곳(주황 사진)과 두 번째 머문 곳(초록 사진 2장)의 썸네일 가운데.
    points: [
      [x, y],
      [x, y + ROW],
      [x + 144, y + ROW],
    ],
  })

  // 핀 5개와 경로 선 3개.
  expect(result.matches).toBeGreaterThan(3000)
  const [first, second, secondNext] = result.points
  const [r1, g1, b1] = first
  expect(r1).toBeGreaterThan(200)
  expect(g1).toBeGreaterThan(100)
  expect(g1).toBeLessThan(180)
  expect(b1).toBeLessThan(100)
  for (const [r, g, b] of [second, secondNext]) {
    expect(g).toBeGreaterThan(r + 50)
    expect(g).toBeGreaterThan(b + 50)
  }
})

test('썸네일이 다 만들어지기 전에 저장해도, 이미지에는 사진이 그려져 있다', async ({ page, timeline }, testInfo) => {
  await slowThumbnails(page, 300)
  await timeline.upload(samples)
  await expect(timeline.summary).toContainText('6장')
  // 썸네일 6장을 만드는 데 2초쯤 걸린다. 그 전에 저장을 누른다.
  const path = testInfo.outputPath('early.png')
  await timeline.saveImage(path)

  // 머문 곳 다섯 줄의 첫 썸네일 가운데. 날짜 구분 줄이 둘째 날 앞에 한 번 더 있다.
  const { x, y } = FIRST_THUMBNAIL
  const rows = [y, y + ROW, y + ROW * 2, y + ROW * 3 + DAY_DIVIDER, y + ROW * 4 + DAY_DIVIDER]
  const { points } = await inspectPNG(page, path, { points: rows.map((row): [number, number] => [x, row]) })
  // 빈 칸은 회색(229, 229, 234)이다. 다섯 줄 모두 사진 색이어야 한다.
  expect(points).toHaveLength(5)
  for (const [r, g, b] of points) {
    expect(Math.max(r, g, b) - Math.min(r, g, b)).toBeGreaterThan(40)
  }
})

test('이미지를 만드는 사이 도착한 장소 이름이 이미지에 들어간다', async ({ page, timeline, services }) => {
  await recordCanvasText(page)
  services.tileDelay = 4000
  await timeline.upload(samples)
  await expect(timeline.cards).toHaveCount(5)
  // 남산(세 번째)의 이름은 약 2초 뒤에 온다. 그 전에 저장을 누른다.
  await expect(timeline.card(2)).toContainText('장소 3')
  await timeline.saveImage()

  const texts = await drawnTexts(page)
  expect(texts).toContain('가짜 남산동')
  expect(texts).not.toContain('장소 3')
  // 이름을 못 받은 곳은 누른 순간의 이름 그대로다.
  expect(texts).toContain('장소 1')
})

test('저장한 이미지의 주소는 몇 초 뒤에도 살아 있다', async ({ page, timeline }) => {
  await recordDownloadHref(page)
  await timeline.upload(samples)
  await expect(timeline.thumbnails).toHaveCount(6)
  await timeline.saveImage()
  // 내려받기 전에 확인 창을 띄우는 브라우저에서는 사용자가 누를 때까지 주소가 살아 있어야 한다.
  await page.waitForTimeout(4000)
  expect(await downloadStillAlive(page)).toBe(true)
})

test('이미지를 만드는 동안에는 저장 버튼이 꺼져 있다', async ({ timeline, services }) => {
  services.tileDelay = 1500
  await timeline.upload(samples)
  await expect(timeline.thumbnails).toHaveCount(6)
  await expect(timeline.saveButton).toHaveText('이미지로 저장')
  const saving = timeline.saveImage()
  await expect(timeline.saveButton).toHaveText('이미지 만드는 중…')
  await expect(timeline.saveButton).toBeDisabled()
  await saving
  await expect(timeline.saveButton).toHaveText('이미지로 저장')
  await expect(timeline.saveButton).toBeEnabled()
})

test('지도 타일을 하나도 받지 못하면 지도 없이 이미지를 만든다', async ({ page, timeline, services }, testInfo) => {
  await recordCanvasText(page)
  // 처음부터 타일이 안 온다(브라우저가 받아 둔 타일을 다시 쓰지 못하게, 실패하는 쪽을 먼저 한다).
  services.tilesFail = true
  await timeline.upload(samples)
  await expect(timeline.thumbnails).toHaveCount(6)
  const withoutMap = testInfo.outputPath('without-map.png')
  await timeline.saveImage(withoutMap)
  const credit = 'Photo Tidy · 지도 © OpenStreetMap'
  // 맨 아래 글자에 지도 출처가 없다.
  expect(await drawnTexts(page)).toContain('Photo Tidy')
  expect(await drawnTexts(page)).not.toContain(credit)

  // 타일이 다시 오면 지도가 들어가고, 그만큼 이미지가 길어진다.
  services.tilesFail = false
  const withMap = testInfo.outputPath('with-map.png')
  await timeline.saveImage(withMap)
  expect(await drawnTexts(page)).toContain(credit)
  const short = await inspectPNG(page, withoutMap)
  const tall = await inspectPNG(page, withMap)
  expect(tall.height - short.height).toBe(MAP_BLOCK)
})

test('머문 곳이 40곳을 넘으면 이미지에는 40곳만 담고 나머지 수를 적는다', async ({ page, timeline }, testInfo) => {
  await recordCanvasText(page)
  // 같은 곳을 45일 동안 하루에 한 장씩 찍었다 → 날마다 머문 곳 하나, 모두 45곳.
  const photos = Array.from({ length: 45 }, (_, index) => {
    const date = new Date(Date.UTC(2026, 0, 1 + index))
    const day = `2026:${String(date.getUTCMonth() + 1).padStart(2, '0')}:${String(date.getUTCDate()).padStart(2, '0')}`
    return withDay(samples[0], testInfo.outputPath(`day-${index}.jpg`), day)
  })
  await timeline.upload(photos)
  await expect(timeline.cards).toHaveCount(45)
  await expect(timeline.summary).toContainText('45장')
  await timeline.saveImage()

  const texts = await drawnTexts(page)
  expect(texts).toContain('외 5곳')
  // 번호는 40번까지만 그린다.
  expect(texts).toContain('40')
  expect(texts).not.toContain('41')
  // 머리말의 장수는 담지 못한 곳까지 포함한다.
  expect(texts.some((text) => text.includes('45장'))).toBe(true)
})
