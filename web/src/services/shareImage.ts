import { fitView, project, tilesFor, TILE_SIZE } from '../core/mercator'
import { retitled, type ShareOutline } from '../core/shareOutline'
import { dayLabel, timeRange } from '../core/timelineText'
import type { TimelineStop } from '../core/types'
import { TILE_ATTRIBUTION, tileURL } from './tiles'

export interface ShareImageOptions {
  outline: ShareOutline
  title: string
  subtitle: string
  /** 사진 id → 그릴 수 있는 주소. 아직 만들지 않은 썸네일은 만들어서 준다. 그리지 못하는 사진이면 undefined. */
  thumbnail: (photoId: string) => Promise<string | undefined>
  /** 이미지를 준비하는 사이 도착한 이름. 없으면 null. */
  lateName: (stop: TimelineStop) => string | null
}

const WIDTH = 1080
const MARGIN = 48
const MAP_HEIGHT = 560
const THUMB = 132
const ACCENT = 'rgb(13, 133, 122)'
const BACKGROUND = '#f2f2f7'
const FONT = '-apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", "Malgun Gothic", "Noto Sans KR", sans-serif'

function loadImage(src: string, crossOrigin: boolean): Promise<HTMLImageElement | null> {
  return new Promise((resolve) => {
    const image = new Image()
    if (crossOrigin) image.crossOrigin = 'anonymous'
    image.onload = () => resolve(image)
    image.onerror = () => resolve(null)
    image.src = src
  })
}

/** 글자가 너비를 넘으면 끝을 …로 줄인다. */
function fitText(context: CanvasRenderingContext2D, text: string, maxWidth: number): string {
  if (context.measureText(text).width <= maxWidth) return text
  let cut = text
  while (cut.length > 1 && context.measureText(`${cut}…`).width > maxWidth) {
    cut = cut.slice(0, -1)
  }
  return `${cut}…`
}

function badge(context: CanvasRenderingContext2D, x: number, y: number, radius: number, number: number) {
  context.beginPath()
  context.arc(x, y, radius, 0, Math.PI * 2)
  context.fillStyle = ACCENT
  context.fill()
  context.lineWidth = 3
  context.strokeStyle = '#fff'
  context.stroke()
  context.fillStyle = '#fff'
  context.font = `700 ${Math.round(radius * 0.95)}px ${FONT}`
  context.textAlign = 'center'
  context.textBaseline = 'middle'
  context.fillText(String(number), x, y + 1)
  context.textAlign = 'left'
  context.textBaseline = 'alphabetic'
}

/** 사진을 정사각형 칸에 꽉 차게(가운데를 잘라) 그린다. */
function drawCover(context: CanvasRenderingContext2D, image: HTMLImageElement, x: number, y: number, size: number) {
  const side = Math.min(image.naturalWidth, image.naturalHeight)
  context.drawImage(image, (image.naturalWidth - side) / 2, (image.naturalHeight - side) / 2, side, side, x, y, size, size)
}

/** 지도 그림. 타일을 하나도 받지 못하면 null. */
async function drawMap(outline: ShareOutline, width: number, height: number): Promise<HTMLCanvasElement | null> {
  const pins = outline.routes.flat()
  const view = fitView(pins.map((pin) => pin.coordinate), width, height, 70, 16)
  if (!view) return null
  const tiles = tilesFor(view.center, view.zoom, width, height)
  const images = await Promise.all(tiles.map((tile) => loadImage(tileURL(tile.x, tile.y, tile.z), true)))
  if (images.every((image) => image === null)) return null

  const canvas = document.createElement('canvas')
  canvas.width = width
  canvas.height = height
  const context = canvas.getContext('2d')!
  context.fillStyle = '#e5e5ea'
  context.fillRect(0, 0, width, height)
  tiles.forEach((tile, index) => {
    const image = images[index]
    if (image) context.drawImage(image, tile.left, tile.top, TILE_SIZE, TILE_SIZE)
  })

  const middle = project(view.center, view.zoom)
  const at = (pin: (typeof pins)[number]) => {
    const point = project(pin.coordinate, view.zoom)
    return { x: point.x - middle.x + width / 2, y: point.y - middle.y + height / 2 }
  }
  // 날짜별로 선을 따로 그린다.
  for (const route of outline.routes) {
    if (route.length < 2) continue
    context.beginPath()
    route.forEach((pin, index) => {
      const { x, y } = at(pin)
      if (index === 0) context.moveTo(x, y)
      else context.lineTo(x, y)
    })
    context.strokeStyle = ACCENT
    context.lineWidth = 6
    context.lineJoin = 'round'
    context.lineCap = 'round'
    context.stroke()
  }
  for (const pin of pins) {
    const { x, y } = at(pin)
    badge(context, x, y, 20, pin.number)
  }
  context.font = `400 18px ${FONT}`
  const credit = TILE_ATTRIBUTION
  const creditWidth = context.measureText(credit).width + 16
  context.fillStyle = 'rgba(255, 255, 255, 0.8)'
  context.fillRect(width - creditWidth, height - 28, creditWidth, 28)
  context.fillStyle = '#333'
  context.fillText(credit, width - creditWidth + 8, height - 8)
  return canvas
}

/** 타임라인을 PNG 한 장으로 만든다(머리말, 지도, 날짜별 머문 곳). */
export async function makeShareImage(options: ShareImageOptions): Promise<Blob> {
  const first = options.outline
  const thumbnailIDs = first.sections.flatMap((section) => section.stops.flatMap((item) => item.thumbnailIDs))
  const loadThumbnails = async () => {
    const loaded = new Map<string, HTMLImageElement | null>()
    // 아직 없는 썸네일은 여기서 만들어진다. 한꺼번에 만들면 메모리를 많이 쓰므로 한 장씩 받는다.
    for (const id of thumbnailIDs) {
      const src = await options.thumbnail(id)
      loaded.set(id, src ? await loadImage(src, false) : null)
    }
    return loaded
  }
  const [mapCanvas, thumbnails] = await Promise.all([drawMap(first, WIDTH - MARGIN * 2, MAP_HEIGHT), loadThumbnails()])
  // 그림을 받는 사이 도착한 장소 이름을 반영한다.
  const outline = retitled(first, options.lateName)
  const withYear = new Set(outline.sections.map((section) => section.day.slice(0, 4))).size > 1

  const rowHeight = 96 + THUMB + 40
  let height = MARGIN + 110
  if (mapCanvas) height += MAP_HEIGHT + 32
  for (const section of outline.sections) {
    height += 64 + section.stops.length * rowHeight
  }
  if (outline.hiddenStops > 0) height += 48
  height += 56 + MARGIN

  const canvas = document.createElement('canvas')
  canvas.width = WIDTH
  canvas.height = height
  const context = canvas.getContext('2d')!
  context.fillStyle = BACKGROUND
  context.fillRect(0, 0, WIDTH, height)

  let y = MARGIN
  context.fillStyle = '#111'
  context.font = `800 52px ${FONT}`
  context.fillText(fitText(context, options.title, WIDTH - MARGIN * 2), MARGIN, y + 50)
  context.fillStyle = '#6b6b70'
  context.font = `400 28px ${FONT}`
  context.fillText(fitText(context, options.subtitle, WIDTH - MARGIN * 2), MARGIN, y + 94)
  y += 110

  if (mapCanvas) {
    context.save()
    context.beginPath()
    context.roundRect(MARGIN, y, WIDTH - MARGIN * 2, MAP_HEIGHT, 24)
    context.clip()
    context.drawImage(mapCanvas, MARGIN, y)
    context.restore()
    y += MAP_HEIGHT + 32
  }

  for (const section of outline.sections) {
    context.fillStyle = ACCENT
    context.font = `700 30px ${FONT}`
    const label = dayLabel(section.day, undefined, withYear)
    context.fillText(label, MARGIN, y + 42)
    const labelWidth = context.measureText(label).width
    context.fillStyle = '#d1d1d6'
    context.fillRect(MARGIN + labelWidth + 20, y + 32, WIDTH - MARGIN * 2 - labelWidth - 20, 2)
    y += 64

    for (const item of section.stops) {
      context.fillStyle = '#fff'
      context.beginPath()
      context.roundRect(MARGIN, y, WIDTH - MARGIN * 2, rowHeight - 20, 24)
      context.fill()

      badge(context, MARGIN + 52, y + 52, 24, item.number)
      context.fillStyle = '#111'
      context.font = `700 32px ${FONT}`
      context.fillText(fitText(context, item.title, WIDTH - MARGIN * 2 - 130), MARGIN + 96, y + 48)
      context.fillStyle = '#6b6b70'
      context.font = `400 24px ${FONT}`
      context.fillText(`${timeRange(item.stop)} · ${item.stop.photos.length}장`, MARGIN + 96, y + 82)

      item.thumbnailIDs.forEach((id, index) => {
        const x = MARGIN + 28 + index * (THUMB + 12)
        const top = y + 104
        context.save()
        context.beginPath()
        context.roundRect(x, top, THUMB, THUMB, 16)
        context.clip()
        context.fillStyle = '#e5e5ea'
        context.fillRect(x, top, THUMB, THUMB)
        const image = thumbnails.get(id)
        if (image) drawCover(context, image, x, top, THUMB)
        context.restore()
      })
      if (item.moreCount > 0) {
        context.fillStyle = '#6b6b70'
        context.font = `600 26px ${FONT}`
        context.fillText(`+${item.moreCount}`, MARGIN + 28 + item.thumbnailIDs.length * (THUMB + 12) + 8, y + 104 + THUMB / 2 + 9)
      }
      y += rowHeight
    }
  }

  context.fillStyle = '#6b6b70'
  if (outline.hiddenStops > 0) {
    context.font = `400 26px ${FONT}`
    context.fillText(`외 ${outline.hiddenStops}곳`, MARGIN, y + 30)
    y += 48
  }
  context.font = `400 22px ${FONT}`
  context.fillText(mapCanvas ? `Photo Tidy · 지도 ${TILE_ATTRIBUTION}` : 'Photo Tidy', MARGIN, y + 36)

  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error('이미지를 만들지 못했습니다.'))), 'image/png')
  })
}

/** 만든 이미지를 파일로 내려받게 한다. */
export function downloadBlob(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = filename
  document.body.append(link)
  link.click()
  link.remove()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}
