// @rails/activestorage は型を同梱していないので、使う分だけ書く
declare module "@rails/activestorage" {
  export class DirectUpload {
    constructor(file: File, url: string, delegate?: {
      directUploadWillCreateBlobWithXHR?: (xhr: XMLHttpRequest) => void
      directUploadWillStoreFileWithXHR?: (xhr: XMLHttpRequest) => void
    })

    create(callback: (error: string | null, blob?: { signed_id: string }) => void): void
  }
}
