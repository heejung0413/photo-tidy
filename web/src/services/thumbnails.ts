/** 썸네일의 짧은 변(픽셀). 화면 칸 80px과 공유 이미지 칸 132px의 2배를 넘는다. */
export const THUMBNAIL_SIZE = 264

/**
 * 사진을 작게 줄인 그림의 주소를 만든다. 원본을 그대로 화면에 올리면 사진이 많을 때 메모리를 너무 쓴다.
 * 브라우저가 그리지 못하는 형식(HEIC 등)이면 null. 다 쓴 주소는 URL.revokeObjectURL로 풀어야 한다.
 */
export async function makeThumbnail(file: File): Promise<string | null> {
  try {
    const bitmap = await createImageBitmap(file)
    const scale = Math.min(1, THUMBNAIL_SIZE / Math.min(bitmap.width, bitmap.height))
    const canvas = document.createElement('canvas')
    canvas.width = Math.round(bitmap.width * scale)
    canvas.height = Math.round(bitmap.height * scale)
    canvas.getContext('2d')!.drawImage(bitmap, 0, 0, canvas.width, canvas.height)
    bitmap.close()
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/jpeg', 0.82))
    return blob ? URL.createObjectURL(blob) : null
  } catch {
    return null
  }
}
