import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, test } from 'vitest'
import { photoId, readPhoto } from './readPhoto'

const fixtures = join(import.meta.dirname, '../../e2e/fixtures')

function fixture(name: string, lastModified = 1_700_000_000_000): File {
  return new File([readFileSync(join(fixtures, name))], name, { type: 'image/jpeg', lastModified })
}

/** 사진 정보가 전혀 없는 1×1 JPEG. */
const plainJPEG = Uint8Array.from(
  atob(
    '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=',
  ),
  (char) => char.charCodeAt(0),
)

describe('readPhoto', () => {
  test('사진에 든 위치와 촬영 시각을 읽는다', async () => {
    const result = await readPhoto(fixture('t1-seongsu.jpg'))
    expect(result).not.toBeNull()
    expect(result!.photo.coordinate!.latitude).toBeCloseTo(37.5446, 4)
    expect(result!.photo.coordinate!.longitude).toBeCloseTo(127.0559, 4)
    // 사진의 촬영 시각에는 시간대가 없다. 보는 사람의 시간대 시각으로 읽는다.
    expect(result!.photo.takenAt).toBe(new Date(2026, 10, 14, 9, 10, 0).getTime())
    expect(result!.usedFileTime).toBe(false)
  })

  test('사진마다 다른 값을 읽는다', async () => {
    const result = await readPhoto(fixture('t6-jamsil.jpg'))
    expect(result!.photo.coordinate!.latitude).toBeCloseTo(37.5133, 4)
    expect(result!.photo.coordinate!.longitude).toBeCloseTo(127.1001, 4)
    expect(result!.photo.takenAt).toBe(new Date(2026, 10, 15, 14, 40, 0).getTime())
  })

  test('정보가 없는 사진은 위치 없이, 파일 시각으로 넣는다', async () => {
    const file = new File([plainJPEG], 'plain.jpg', { type: 'image/jpeg', lastModified: 1_600_000_000_000 })
    const result = await readPhoto(file)
    expect(result!.photo.coordinate).toBeNull()
    expect(result!.photo.takenAt).toBe(1_600_000_000_000)
    expect(result!.usedFileTime).toBe(true)
  })

  test('사진이 아닌 파일은 null', async () => {
    expect(await readPhoto(new File(['메모'], 'memo.txt', { type: 'text/plain' }))).toBeNull()
  })

  test('종류 표시가 없어도 확장자가 사진이면 받는다', async () => {
    const file = new File([plainJPEG], 'IMG_0001.HEIC', { type: '', lastModified: 1_600_000_000_000 })
    expect(await readPhoto(file)).not.toBeNull()
  })

  test('사진 id는 이름·크기·수정 시각으로 만든다', async () => {
    const file = fixture('t1-seongsu.jpg', 123)
    expect(photoId(file)).toBe(`t1-seongsu.jpg|${file.size}|123`)
    expect((await readPhoto(file))!.photo.id).toBe(photoId(file))
  })
})
