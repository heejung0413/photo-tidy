import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

const fixtures = join(import.meta.dirname, '..', 'fixtures')

/** 샘플 6장. 2026-11-14에 3곳 4장(서울숲 2장은 한 곳), 11-15에 2곳 2장. */
export const samples = ['t1-seongsu', 't2-forest', 't3-forest', 't4-namsan', 't5-gangnam', 't6-jamsil'].map((name) =>
  join(fixtures, `${name}.jpg`),
)

/** 샘플과 다른 곳(시드니)의 사진 한 장. */
export const sydney = join(import.meta.dirname, '..', '..', 'src', 'services', 'fixtures', 'sydney.jpg')

/** 사진이 아닌 파일. */
export const notAPhoto = join(import.meta.dirname, 'samples.ts')

/** 1×1 투명 PNG. 위치도 촬영 시각도 들어 있지 않다. */
export const blankPNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  'base64',
)

/** 샘플을 이름만 바꿔 count개로 늘린다(이름이 다르면 다른 사진으로 본다). 읽는 데 시간이 걸리게 하려는 것. */
export function manyCopies(directory: string, count: number): string[] {
  mkdirSync(directory, { recursive: true })
  return Array.from({ length: count }, (_, index) => {
    const path = join(directory, `copy-${index}.jpg`)
    copyFileSync(samples[index % samples.length], path)
    return path
  })
}

/** 위치도 촬영 시각도 없는 사진을 directory에 만들고 그 경로를 돌려준다. */
export function plainPhoto(directory: string): string {
  mkdirSync(directory, { recursive: true })
  const path = join(directory, 'plain.png')
  writeFileSync(path, blankPNG)
  return path
}

/**
 * 사진 정보(EXIF)의 위도에서 "도" 값만 degrees로 바꾼 사본을 만든다.
 * 90을 넘는 값을 주면 지구에 없는 좌표가 된다(위치 정보가 깨진 사진을 흉내 낸다).
 */
export function withLatitudeDegrees(source: string, destination: string, degrees: number): string {
  const data = Buffer.from(readFileSync(source))
  // JPEG 조각을 차례로 넘기며 사진 정보가 든 조각(APP1 "Exif")을 찾는다.
  let segment = 2
  while (!(data.readUInt16BE(segment) === 0xffe1 && data.toString('latin1', segment + 4, segment + 8) === 'Exif')) {
    segment += 2 + data.readUInt16BE(segment + 2)
    if (segment >= data.length) throw new Error(`사진 정보가 없는 파일: ${source}`)
  }
  const start = segment + 10
  const little = data.toString('latin1', start, start + 2) === 'II'
  const u16 = (at: number) => (little ? data.readUInt16LE(start + at) : data.readUInt16BE(start + at))
  const u32 = (at: number) => (little ? data.readUInt32LE(start + at) : data.readUInt32BE(start + at))
  /** 목록(IFD)에서 tag의 값 칸에 적힌 숫자. */
  const entry = (list: number, tag: number): number => {
    for (let index = 0; index < u16(list); index += 1) {
      const at = list + 2 + index * 12
      if (u16(at) === tag) return u32(at + 8)
    }
    throw new Error(`사진 정보에 ${tag.toString(16)} 항목이 없는 파일: ${source}`)
  }
  // 0x8825: 위치 정보 목록의 위치. 그 안의 2번: 위도(도·분·초, 각각 분자/분모).
  const latitude = start + entry(entry(u32(4), 0x8825), 2)
  if (little) {
    data.writeUInt32LE(degrees, latitude)
    data.writeUInt32LE(1, latitude + 4)
  } else {
    data.writeUInt32BE(degrees, latitude)
    data.writeUInt32BE(1, latitude + 4)
  }
  writeFileSync(destination, data)
  return destination
}
