import exifr from 'exifr'
import type { TimelinePhoto } from '../core/types'

export interface ReadResult {
  photo: TimelinePhoto
  /** 사진에 촬영 시각이 없어 파일 수정 시각을 썼다. */
  usedFileTime: boolean
}

const PHOTO_EXTENSIONS = /\.(jpe?g|png|heic|heif|webp|tiff?|avif)$/i

/** 같은 파일을 다시 올려도 같은 값이 되는 id. */
export function photoId(file: File): string {
  return `${file.name}|${file.size}|${file.lastModified}`
}

function isPhoto(file: File): boolean {
  return file.type.startsWith('image/') || PHOTO_EXTENSIONS.test(file.name)
}

const validNumber = (value: unknown): value is number => typeof value === 'number' && Number.isFinite(value)

/**
 * 사진 파일에서 위치와 촬영 시각을 읽는다. 사진이 아니면 null.
 * 사진이지만 정보가 없거나 읽지 못하면 위치 없이, 파일 수정 시각으로 넣는다.
 */
export async function readPhoto(file: File): Promise<ReadResult | null> {
  if (!isPhoto(file)) {
    return null
  }
  let coordinate: TimelinePhoto['coordinate'] = null
  let takenAt: number | null = null
  try {
    const data = await exifr.parse(await file.arrayBuffer(), {
      gps: true,
      pick: ['DateTimeOriginal', 'CreateDate', 'GPSLatitude', 'GPSLatitudeRef', 'GPSLongitude', 'GPSLongitudeRef'],
    })
    if (validNumber(data?.latitude) && validNumber(data?.longitude)) {
      coordinate = { latitude: data.latitude, longitude: data.longitude }
    }
    const date: unknown = data?.DateTimeOriginal ?? data?.CreateDate
    if (date instanceof Date && !Number.isNaN(date.getTime())) {
      takenAt = date.getTime()
    }
  } catch {
    // 정보를 읽지 못한 사진도 타임라인에는 넣는다.
  }
  return {
    photo: { id: photoId(file), takenAt: takenAt ?? file.lastModified, coordinate },
    usedFileTime: takenAt === null,
  }
}
