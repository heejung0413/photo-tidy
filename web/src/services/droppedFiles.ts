import { collectFiles, type DroppedEntry } from '../core/droppedEntries'

function adapt(entry: FileSystemEntry): DroppedEntry<File> {
  if (entry.isDirectory) {
    return {
      kind: 'directory',
      name: entry.name,
      reader: () => {
        const reader = (entry as FileSystemDirectoryEntry).createReader()
        return () =>
          new Promise<DroppedEntry<File>[]>((resolve, reject) =>
            reader.readEntries((entries) => resolve(entries.map(adapt)), reject),
          )
      },
    }
  }
  return {
    kind: 'file',
    name: entry.name,
    file: () => new Promise<File>((resolve, reject) => (entry as FileSystemFileEntry).file(resolve, reject)),
  }
}

/**
 * 떨어뜨린 것에서 파일을 전부 꺼낸다. 폴더를 떨어뜨리면 그 안의 파일(폴더 속 폴더 포함)을 꺼낸다.
 * 떨어뜨린 내용은 이벤트 처리가 끝나면 읽을 수 없으므로, 이벤트 처리 함수 안에서 바로 불러야 한다.
 */
export function filesFromDrop(transfer: DataTransfer | null): Promise<File[]> {
  if (!transfer) {
    return Promise.resolve([])
  }
  const entries: DroppedEntry<File>[] = []
  for (const item of transfer.items) {
    if (item.kind !== 'file') continue
    const entry = item.webkitGetAsEntry?.() ?? null
    if (entry) {
      entries.push(adapt(entry))
    } else {
      const file = item.getAsFile()
      if (file) entries.push({ kind: 'file', name: file.name, file: async () => file })
    }
  }
  return collectFiles(entries)
}
