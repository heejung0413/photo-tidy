import type { Page } from '@playwright/test'
import { readFileSync } from 'node:fs'

export type RGB = [number, number, number]

export interface Region {
  x: number
  y: number
  width: number
  height: number
  /** 이 색과 비슷한 픽셀을 센다. */
  color: RGB
  /** 색 성분마다 이 값 미만으로 차이 나면 비슷한 색으로 본다. */
  tolerance: number
}

export interface Inspection {
  width: number
  height: number
  /** 물어본 점들의 색(물어본 순서). */
  points: RGB[]
  /** region 안에서 color와 비슷한 픽셀 수. region을 주지 않았으면 0. */
  matches: number
}

/**
 * 저장한 PNG를 브라우저에서 다시 열어 크기와 픽셀을 읽는다.
 * (노드에는 PNG를 푸는 기능이 없어서, 테스트 중인 페이지의 캔버스를 빌려 쓴다.)
 */
export function inspectPNG(
  page: Page,
  path: string,
  query: { points?: [number, number][]; region?: Region } = {},
): Promise<Inspection> {
  return page.evaluate(
    async ({ url, points, region }) => {
      const image = new Image()
      image.src = url
      await image.decode()
      const canvas = document.createElement('canvas')
      canvas.width = image.naturalWidth
      canvas.height = image.naturalHeight
      const context = canvas.getContext('2d')!
      context.drawImage(image, 0, 0)
      const pixel = (x: number, y: number) => [...context.getImageData(x, y, 1, 1).data.slice(0, 3)] as RGB
      let matches = 0
      if (region) {
        const data = context.getImageData(region.x, region.y, region.width, region.height).data
        for (let i = 0; i < data.length; i += 4) {
          if (region.color.every((value, channel) => Math.abs(data[i + channel] - value) < region.tolerance)) {
            matches += 1
          }
        }
      }
      return { width: canvas.width, height: canvas.height, points: points.map(([x, y]) => pixel(x, y)), matches }
    },
    {
      url: `data:image/png;base64,${readFileSync(path).toString('base64')}`,
      points: query.points ?? [],
      region: query.region ?? null,
    },
  )
}
