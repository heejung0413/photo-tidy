import { samples, withDay, withLatitudeDegrees } from './support/samples.ts'
import { expect, test } from './support/test.ts'

// 장소 이름: 서비스에서 받아 오기, 요청 간격, 실패했을 때, 직접 고치기.

test('받아 온 장소 이름을 보여 주고, 못 받은 곳은 번호 이름으로 둔다', async ({ timeline }) => {
  await timeline.upload(samples)
  // 이름은 약 1초에 하나씩 받는다. 남산은 세 번째 머문 곳이다.
  await expect(timeline.card(2)).toContainText('가짜 남산동', { timeout: 15_000 })
  await expect(timeline.card(0)).toContainText('장소 1')
})

test('장소 이름은 머문 곳마다 한 번씩, 1초 넘게 띄워서 묻는다', async ({ page, timeline, services }) => {
  await timeline.upload(samples)
  await expect(timeline.cards).toHaveCount(5)
  await expect.poll(() => services.nameRequests.length, { timeout: 15_000 }).toBe(5)
  // 더 기다려도 다시 묻지 않는다.
  await page.waitForTimeout(2500)
  expect(services.nameRequests).toHaveLength(5)
  const gaps = services.nameRequests.slice(1).map((time, index) => time - services.nameRequests[index])
  expect(Math.min(...gaps)).toBeGreaterThanOrEqual(1000)
})

test('이름 요청이 연달아 실패해 쉬었다가, 쉬는 시간이 지나면 다시 묻는다', async ({ page, timeline, services }) => {
  await page.clock.install()
  // 처음 세 번은 인터넷이 끊긴 것처럼 실패시킨다.
  services.nameReply = ({ count }) => (count <= 3 ? 'abort' : { address: { suburb: `동네${count}` } })
  const requests = () => services.nameRequests.length
  await timeline.upload(samples)
  await expect(timeline.cards).toHaveCount(5)
  await expect.poll(requests, { timeout: 15_000 }).toBe(3)
  // 세 번 실패한 뒤에는 쉰다. 남은 두 곳은 묻지 않는다.
  await page.clock.runFor(5000)
  expect(requests()).toBe(3)
  await expect(timeline.card(0)).toContainText('장소 1')

  // 1분 남짓 지나면 다시 물어 다섯 곳 모두 이름이 붙는다.
  await page.clock.runFor(90_000)
  await expect.poll(requests, { timeout: 15_000 }).toBe(8)
  for (let index = 0; index < 5; index += 1) {
    await expect(timeline.card(index)).toContainText('동네')
  }
})

test('잘못된 좌표의 머문 곳이 있어도 다른 장소는 이름을 받는다', async ({ page, timeline, services }, testInfo) => {
  // 알려진 문제(2026-11-18 검토 2번, llm-wiki/known-issues.md): 아직 고치지 않아 실패하는 것이 정상이다.
  // 고치면 이 테스트가 "예상과 달리 통과"로 빨개진다. 그때 아래 줄을 지운다.
  test.fail()

  await page.clock.install()
  // 첫날 사진 4장의 위도를 200도로 바꾼다 → 지구에 없는 좌표의 머문 곳 3곳이 앞쪽에 온다.
  const broken = samples
    .slice(0, 4)
    .map((path, index) => withLatitudeDegrees(path, testInfo.outputPath(`broken-${index}.jpg`), 200))
  // 서비스는 범위를 벗어난 좌표를 매번 거절한다.
  services.nameReply = ({ latitude }) => (Math.abs(latitude) > 90 ? { status: 400 } : { address: { suburb: '정상동' } })
  await timeline.upload([...broken, ...samples.slice(4)])
  await expect(timeline.cards).toHaveCount(5)
  await expect.poll(() => services.nameRequests.length, { timeout: 15_000 }).toBeGreaterThanOrEqual(3)

  // 쉬는 시간을 두 번 넘겨도, 둘째 날의 정상 좌표 두 곳은 이름을 받아야 한다.
  await page.clock.runFor(90_000)
  await page.clock.runFor(90_000)
  await expect(timeline.card(3)).toContainText('정상동', { timeout: 10_000 })
  await expect(timeline.card(4)).toContainText('정상동', { timeout: 10_000 })
})

test('장소 이름을 고치면 바뀌고, 다시 방문해도 남는다', async ({ page, timeline }) => {
  await timeline.upload(samples)
  const first = timeline.card(0)
  await first.getByRole('button', { name: '장소 이름 바꾸기' }).click()
  await first.getByRole('textbox', { name: '장소 이름' }).fill('우리 카페')
  await first.getByRole('button', { name: '저장' }).click()
  await expect(first).toContainText('우리 카페')
  // 옆 장소는 그대로다.
  await expect(timeline.card(1)).not.toContainText('우리 카페')

  await page.reload()
  await timeline.upload(samples)
  await expect(timeline.card(0)).toContainText('우리 카페')

  // 비워서 저장하면 자동 이름으로 돌아간다.
  const again = timeline.card(0)
  await again.getByRole('button', { name: '장소 이름 바꾸기' }).click()
  await expect(again.getByRole('textbox', { name: '장소 이름' })).toHaveValue('우리 카페')
  await again.getByRole('textbox', { name: '장소 이름' }).fill('')
  await again.getByRole('button', { name: '저장' }).click()
  await expect(again).toContainText('장소 1')
})

test('이름 고치기를 취소하면 바뀌지 않는다', async ({ timeline }) => {
  await timeline.upload(samples)
  const first = timeline.card(0)
  await first.getByRole('button', { name: '장소 이름 바꾸기' }).click()
  await first.getByRole('textbox', { name: '장소 이름' }).fill('잘못 쓴 이름')
  await first.getByRole('button', { name: '취소' }).click()
  await expect(first.getByRole('textbox', { name: '장소 이름' })).toHaveCount(0)
  await expect(first).toContainText('장소 1')
  // 다시 열면 쓰다 만 글자가 남아 있지 않다.
  await first.getByRole('button', { name: '장소 이름 바꾸기' }).click()
  await expect(first.getByRole('textbox', { name: '장소 이름' })).toHaveValue('')
})

test('다른 날 같은 곳은 직접 붙인 이름을 물려받고, 따로 고쳐도 원래 장소는 그대로다', async ({ timeline }, testInfo) => {
  // 첫 사진(성수)과 같은 곳에서 엿새 뒤에 찍은 사진.
  const later = withDay(samples[0], testInfo.outputPath('later.jpg'), '2026:11:20')
  await timeline.upload([...samples, later])
  await expect(timeline.cards).toHaveCount(6)
  await expect(timeline.dayDividers).toHaveCount(3)

  await timeline.rename(0, '우리 카페')
  await expect(timeline.card(0)).toContainText('우리 카페')
  await expect(timeline.card(5)).toContainText('우리 카페')
  // 떨어진 장소는 물려받지 않는다.
  await expect(timeline.card(1)).not.toContainText('우리 카페')

  await timeline.rename(5, '그날 간 식당')
  await expect(timeline.card(5)).toContainText('그날 간 식당')
  await expect(timeline.card(0)).toContainText('우리 카페')
})

test('받아 둔 장소 이름은 다시 방문하면 바로 나오고, 다시 묻지 않는다', async ({ page, timeline, services }) => {
  await timeline.upload(samples)
  await expect(timeline.card(2)).toContainText('가짜 남산동', { timeout: 15_000 })
  await expect.poll(() => services.nameQueries.length, { timeout: 15_000 }).toBe(5)

  await page.reload()
  await timeline.upload(samples)
  // 이름을 받으려면 1초 넘게 걸리지만, 받아 둔 이름은 기다리지 않고 나온다.
  await expect(timeline.card(2)).toContainText('가짜 남산동', { timeout: 1000 })
  // 이름이 없다고 답했던 네 곳만 다시 묻는다(그 답은 방문 동안만 기억한다).
  await expect.poll(() => services.nameQueries.length, { timeout: 15_000 }).toBe(9)
  await page.waitForTimeout(1500)
  const again = services.nameQueries.slice(5)
  expect(again).toHaveLength(4)
  expect(again.filter((query) => Math.abs(query.latitude - 37.5512) < 0.001)).toHaveLength(0)
})
