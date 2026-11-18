import { plainPhoto, samples } from './support/samples.ts'
import { expect, test } from './support/test.ts'

// 지도: 핀, 창 크기가 바뀔 때의 범위, 좁은 화면.

test('좁은 화면에서 머문 곳을 누르면 지도가 보이는 곳으로 올라간다', async ({ page, timeline }) => {
  await page.setViewportSize({ width: 390, height: 700 })
  await timeline.upload(samples)
  await expect(timeline.cards).toHaveCount(5)
  const last = timeline.card(4)
  await last.scrollIntoViewIfNeeded()
  await expect(timeline.map).not.toBeInViewport()
  await last.locator('.stop-main').click()
  await expect(timeline.map).toBeInViewport({ ratio: 0.9 })
})

test('지도를 직접 확대한 뒤에는 창 크기가 바뀌어도 전체 범위로 돌아가지 않는다', async ({ page, timeline }) => {
  await timeline.upload(samples)
  await expect(timeline.pins).toHaveCount(5)
  await page.waitForTimeout(500)
  const before = await timeline.pinSpacing()
  await page.locator('.leaflet-control-zoom-in').click()
  await page.waitForTimeout(600)
  await page.locator('.leaflet-control-zoom-in').click()
  await page.waitForTimeout(600)
  const zoomed = await timeline.pinSpacing()
  expect(zoomed).toBeGreaterThan(before * 3)

  await page.setViewportSize({ width: 1180, height: 860 })
  await page.waitForTimeout(800)
  expect(await timeline.pinSpacing()).toBeCloseTo(zoomed, 0)
})

test('창 크기가 바뀌면, 직접 건드리지 않은 지도는 핀이 모두 보이게 다시 맞춘다', async ({ page, timeline }) => {
  await timeline.upload(samples)
  await expect(timeline.pins).toHaveCount(5)
  await page.setViewportSize({ width: 500, height: 800 })
  await page.waitForTimeout(800)
  const map = (await timeline.map.boundingBox())!
  for (let index = 0; index < 5; index += 1) {
    const pin = (await timeline.pins.nth(index).boundingBox())!
    expect(pin.x).toBeGreaterThanOrEqual(map.x)
    expect(pin.x + pin.width).toBeLessThanOrEqual(map.x + map.width)
  }
})

test('장소 이름이 도착해도 지도의 핀을 새로 만들지 않는다', async ({ timeline }) => {
  await timeline.upload(samples)
  await expect(timeline.pins).toHaveCount(5)
  // 처음 그려진 핀에 표시를 해 둔다.
  await timeline.pins.evaluateAll((pins) => pins.forEach((pin) => pin.setAttribute('data-first', 'yes')))
  // 세 번째 머문 곳의 이름이 도착할 때까지 기다린다.
  await expect(timeline.card(2)).toContainText('가짜 남산동', { timeout: 15_000 })
  await expect(timeline.page.locator('.map-pin[data-first="yes"]')).toHaveCount(5)
  // 핀의 이름은 새 이름으로 바뀌어 있다.
  await expect(timeline.pins.nth(2)).toHaveAttribute('title', '가짜 남산동')
})

test('머문 곳을 누르면 지도가 그곳으로 옮겨 가 확대된다', async ({ page, timeline }) => {
  await timeline.upload(samples)
  await expect(timeline.pins).toHaveCount(5)
  await page.waitForTimeout(500)
  const before = await timeline.pinSpacing()
  await timeline.card(3).locator('.stop-main').click()

  // 넷째 머문 곳의 핀이 지도 한가운데에 온다.
  const offCenter = async () => {
    const map = (await timeline.map.boundingBox())!
    const pin = (await timeline.pins.nth(3).boundingBox())!
    return Math.hypot(pin.x + pin.width / 2 - (map.x + map.width / 2), pin.y + pin.height / 2 - (map.y + map.height / 2))
  }
  await expect.poll(offCenter, { timeout: 5000 }).toBeLessThan(5)
  // 전체가 보이던 때보다 훨씬 확대돼 있다.
  expect(await timeline.pinSpacing()).toBeGreaterThan(before * 3)
})

test('위치 없는 머문 곳은 누를 수 없다', async ({ timeline }, testInfo) => {
  await timeline.upload([...samples.slice(0, 1), plainPhoto(testInfo.outputPath('plain'))])
  await expect(timeline.cards).toHaveCount(2)
  const located = timeline.cards.filter({ hasNotText: '위치 정보 없음' })
  const unlocated = timeline.cards.filter({ hasText: '위치 정보 없음' })
  await expect(located.locator('.stop-main')).toBeEnabled()
  await expect(unlocated.locator('.stop-main')).toBeDisabled()
})

test('경로 선은 날짜별로 따로 그린다', async ({ timeline }) => {
  await timeline.upload(samples)
  await expect(timeline.pins).toHaveCount(5)
  // 첫날 3곳을 잇는 선 하나, 둘째 날 2곳을 잇는 선 하나. 두 날을 잇는 선은 없다.
  await expect(timeline.routeLines).toHaveCount(2)
})

test('장소 이름을 고치면 지도 핀의 이름도 바뀐다', async ({ timeline }) => {
  await timeline.upload(samples)
  await expect(timeline.pins).toHaveCount(5)
  await timeline.rename(0, '우리 카페')
  await expect(timeline.pins.nth(0)).toHaveAttribute('title', '우리 카페')
  await expect(timeline.pins.nth(1)).not.toHaveAttribute('title', '우리 카페')
})
