export const preloadedImageUrls = new Set();

export function preloadImage(url: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = async () => {
      try {
        await img.decode();
        preloadedImageUrls.add(url);
      } catch {
        // Keep the previous preload contract: a successfully loaded image still resolves.
        // It simply is not marked as pre-decoded for `Image` consumers.
      }
      resolve(img);
    };
    img.onerror = reject;
    img.src = url;
  });
}
