import { expect, test, type Page } from '@playwright/test'
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

/** 바깥 서비스(지도 타일, 장소 이름)를 가짜 응답으로 바꾼다. 받은 이름 요청을 돌려준다. */
async function stubServices(page: Page) {
  const nameRequests: string[] = []
  await page.route('https://tile.openstreetmap.org/**', (route) =>
    route.fulfill({ contentType: 'image/png', body: blankTile, headers: { 'access-control-allow-origin': '*' } }),
  )
  await page.route('https://nominatim.openstreetmap.org/**', (route) => {
    const url = new URL(route.request().url())
    nameRequests.push(url.search)
    const latitude = Number(url.searchParams.get('lat'))
    // 남산 근처만 이름을 주고, 나머지는 이름 없는 응답을 준다.
    const address = Math.abs(latitude - 37.5512) < 0.001 ? { suburb: '가짜 남산동' } : {}
    return route.fulfill({ json: { address }, headers: { 'access-control-allow-origin': '*' } })
  })
  return nameRequests
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
