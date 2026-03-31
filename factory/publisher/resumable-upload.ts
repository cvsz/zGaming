export interface UploadChunk {
  index: number;
  totalChunks: number;
  payload: Uint8Array;
  uploadId: string;
}

export interface UploadProgress {
  uploadId: string;
  receivedChunks: number;
  totalChunks: number;
  complete: boolean;
}

/**
 * In-memory stateless-friendly coordinator.
 * State is serializable and can be persisted in Redis/Postgres by caller.
 */
export class ResumableUploadCoordinator {
  private readonly uploads = new Map<string, Map<number, Uint8Array>>();

  acceptChunk(chunk: UploadChunk): UploadProgress {
    if (chunk.totalChunks <= 0 || chunk.index < 0 || chunk.index >= chunk.totalChunks) {
      throw new Error("invalid chunk metadata");
    }

    const upload = this.uploads.get(chunk.uploadId) ?? new Map<number, Uint8Array>();
    upload.set(chunk.index, chunk.payload);
    this.uploads.set(chunk.uploadId, upload);

    return {
      uploadId: chunk.uploadId,
      receivedChunks: upload.size,
      totalChunks: chunk.totalChunks,
      complete: upload.size === chunk.totalChunks,
    };
  }

  finalize(uploadId: string, totalChunks: number): Uint8Array {
    const upload = this.uploads.get(uploadId);
    if (!upload || upload.size !== totalChunks) {
      throw new Error(`upload ${uploadId} is incomplete`);
    }

    const sorted = Array.from(upload.entries()).sort(([a], [b]) => a - b);
    const merged = sorted.flatMap(([, payload]) => Array.from(payload));
    this.uploads.delete(uploadId);
    return new Uint8Array(merged);
  }
}
