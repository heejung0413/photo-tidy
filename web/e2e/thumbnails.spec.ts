import { slowThumbnails } from './support/browserHooks.ts'
import { samples, sydney } from './support/samples.ts'
import { expect, test } from './support/test.ts'

// 썸네일: 원본 대신 작게 줄인 그림을 사진 읽기와 따로 만든다.

test('썸네일은 원본이 아니라 작게 줄인 그림이다', async ({ timeline }) => {
  await timeline.upload(samples)
  await expect(timeline.thumbnails).toHaveCount(6)
  const sizes = await timeline.thumbnails.evaluateAll((images) =>
    images.map((image) => {
      const { naturalWidth, naturalHeight } = image as HTMLImageElement
      return Math.min(naturalWidth, naturalHeight)
    }),
  )
  // 샘플 원본은 1200×900. 짧은 변을 264로 줄인다.
  expect(sizes).toEqual([264, 264, 264, 264, 264, 264])
})

test('앞 묶음의 썸네일을 만드는 중에도 다음 묶음을 바로 읽는다', async ({ page, timeline }) => {
  await slowThumbnails(page, 500)
  await timeline.upload(samples)
  await expect(timeline.summary).toContainText('6장')
  // 썸네일 6장에 3초쯤 걸린다. 그사이 한 장을 더 올린다.
  await timeline.upload([sydney])
  await expect(timeline.summary).toContainText('7장', { timeout: 1500 })
})
