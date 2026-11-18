import { copyFileSync, mkdirSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { manyCopies, notAPhoto, plainPhoto, samples, sydney } from './support/samples.ts'
import { expect, test } from './support/test.ts'

// 사진을 올리고(고르기, 끌어다 놓기, 폴더째), 지우는 흐름.

test('샘플 사진을 올리면 날짜별 머문 곳이 나온다', async ({ page, timeline }) => {
  await expect(timeline.emptyMessage).toBeVisible()
  await timeline.upload(samples)

  await expect(timeline.dayDividers).toHaveCount(2)
  await expect(timeline.dayDividers.nth(0)).toContainText('11월 14일')
  await expect(timeline.dayDividers.nth(1)).toContainText('11월 15일')
  // 첫날 3곳(서울숲 2장은 한 곳), 둘째 날 2곳.
  await expect(timeline.cards).toHaveCount(5)
  await expect(timeline.summary).toContainText('6장')
  await expect(timeline.summary).toContainText('2026년 11월 14일')
  await expect(timeline.card(1)).toContainText('2장')
  await expect(timeline.card(0)).toContainText('오전 9:10')
  await expect(timeline.card(1)).toContainText('오전 11:05–오전 11:20')

  // 지도에 번호 핀 5개.
  await expect(timeline.pins).toHaveCount(5)
  await expect(timeline.pins.nth(4)).toHaveText('5')
  await page.screenshot({ path: 'test-results/shots/1-timeline.png', fullPage: true })
})

test('같은 사진을 다시 올려도 한 번만 들어간다', async ({ timeline }) => {
  await timeline.upload(samples.slice(0, 3))
  await expect(timeline.summary).toContainText('3장')
  await timeline.upload(samples)
  await expect(timeline.summary).toContainText('6장')
  await expect(timeline.cards).toHaveCount(5)
})

test('사진이 아닌 파일은 건너뛰고 알린다', async ({ page, timeline }) => {
  await timeline.upload([notAPhoto, samples[0]])
  await expect(page.getByText('읽지 못한 파일 1개')).toBeVisible()
  await expect(timeline.summary).toContainText('1장')
})

test('읽지 못한 파일 안내는 다음에 올릴 때 지워진다', async ({ page, timeline }) => {
  await timeline.upload([notAPhoto])
  await expect(page.getByText('읽지 못한 파일 1개')).toBeVisible()
  await timeline.upload(samples)
  await expect(timeline.summary).toContainText('6장')
  await expect(page.getByText('읽지 못한 파일')).toHaveCount(0)
})

test('위치 없는 사진만 올리면 지도 대신 안내가 나온다', async ({ page, timeline }, testInfo) => {
  await timeline.upload([plainPhoto(testInfo.outputPath('plain'))])
  await expect(timeline.summary).toContainText('1장')
  await expect(timeline.cards).toHaveCount(1)
  await expect(timeline.card(0)).toContainText('위치 정보 없음')
  await expect(page.getByText('올린 사진에 위치 정보가 없어 지도를 표시하지 못해요.')).toBeVisible()
  await expect(timeline.map).toHaveCount(0)

  // 위치 있는 사진을 더 올리면 지도가 나오고 안내는 사라진다.
  await timeline.upload(samples.slice(0, 1))
  await expect(timeline.pins).toHaveCount(1)
  await expect(page.getByText('지도를 표시하지 못해요')).toHaveCount(0)
})

test('촬영 시각이 없는 사진은 파일 시각을 썼다고 알린다', async ({ page, timeline }, testInfo) => {
  // 촬영 시각이 든 샘플만 올리면 안내가 없다.
  await timeline.upload(samples)
  await expect(timeline.summary).toContainText('6장')
  await expect(page.getByText('파일 시각을 쓴 사진')).toHaveCount(0)

  await timeline.upload([plainPhoto(testInfo.outputPath('plain'))])
  await expect(timeline.summary).toContainText('7장')
  await expect(page.getByText('촬영 시각이 없어 파일 시각을 쓴 사진 1장')).toBeVisible()
})

test('전부 지우면 처음 화면으로 돌아간다', async ({ timeline }) => {
  await timeline.upload(samples)
  await expect(timeline.cards).toHaveCount(5)
  await timeline.clear()
  await expect(timeline.cards).toHaveCount(0)
  await expect(timeline.emptyMessage).toBeVisible()
})

test('읽는 도중 전부 지우면, 읽던 사진이 되살아나지 않는다', async ({ page, timeline }, testInfo) => {
  await timeline.upload(samples)
  await expect(timeline.cards).toHaveCount(5)
  await timeline.upload(manyCopies(testInfo.outputPath('copies'), 400))
  await expect(timeline.readingStatus).toContainText('사진을 읽는 중')
  await timeline.clear()

  await expect(timeline.emptyMessage).toBeVisible()
  await expect(timeline.readingStatus).toHaveCount(0)
  // 읽기가 끝날 만큼 기다려도 처음 화면 그대로다.
  await page.waitForTimeout(3000)
  await expect(timeline.cards).toHaveCount(0)
  await expect(timeline.emptyMessage).toBeVisible()

  // 지운 뒤 다시 올리면 정상으로 들어간다.
  await timeline.upload(samples)
  await expect(timeline.summary).toContainText('6장')
})

test('묶음을 연달아 올리고 읽는 중에 전부 지우면, 기다리던 묶음도 올라오지 않는다', async ({ page, timeline }, testInfo) => {
  await timeline.upload(samples)
  await expect(timeline.cards).toHaveCount(5)
  await timeline.upload(manyCopies(testInfo.outputPath('first'), 400))
  await timeline.upload(manyCopies(testInfo.outputPath('second'), 30))
  await expect(timeline.readingStatus).toContainText('사진을 읽는 중')
  await timeline.clear()

  await expect(timeline.emptyMessage).toBeVisible()
  await page.waitForTimeout(4000)
  await expect(timeline.cards).toHaveCount(0)
  await expect(timeline.emptyMessage).toBeVisible()
  await expect(timeline.readingStatus).toHaveCount(0)
})

test('올리는 영역 밖에 떨어뜨려도 사진을 받는다', async ({ timeline }) => {
  await timeline.upload(samples.slice(0, 1))
  await expect(timeline.summary).toContainText('1장')
  const prevented = await timeline.dropFile(samples[5])
  // 막지 않으면 브라우저가 그 사진 파일로 이동해 타임라인이 사라진다.
  expect(prevented).toBe(true)
  await expect(timeline.summary).toContainText('2장')
})

test('사진이 든 폴더를 통째로 떨어뜨리면 그 안의 사진을 받는다', async ({ page, timeline }, testInfo) => {
  // 폴더 안에 날짜별 폴더, 메모 파일, 숨김 파일이 섞여 있다.
  const trip = testInfo.outputPath('trip')
  mkdirSync(join(trip, 'day1'), { recursive: true })
  mkdirSync(join(trip, 'day2'), { recursive: true })
  samples.slice(0, 4).forEach((path, index) => copyFileSync(path, join(trip, 'day1', `a${index}.jpg`)))
  samples.slice(4).forEach((path, index) => copyFileSync(path, join(trip, 'day2', `b${index}.jpg`)))
  writeFileSync(join(trip, 'notes.txt'), '메모')
  writeFileSync(join(trip, '.DS_Store'), '')

  await timeline.dropFolder(trip)

  await expect(timeline.summary).toContainText('6장')
  await expect(timeline.cards).toHaveCount(5)
  // 메모 파일만 읽지 못한 파일로 센다. 숨김 파일과 폴더 자체는 세지 않는다.
  await expect(page.getByText('읽지 못한 파일 1개')).toBeVisible()
})

test('페이지 안의 썸네일을 끌었다 놓아도 새 사진으로 올라가지 않는다', async ({ page, timeline }) => {
  await timeline.upload(samples)
  await expect(timeline.thumbnails).toHaveCount(6)
  await expect(timeline.thumbnails.first()).toHaveAttribute('draggable', 'false')
  await timeline.dragThumbnailOntoPage(samples[0])
  await page.waitForTimeout(800)
  await expect(timeline.summary).toContainText('6장')

  // 그 뒤에 밖에서 끌어온 파일은 정상으로 받는다.
  await timeline.dropFile(sydney)
  await expect(timeline.summary).toContainText('7장')
})
