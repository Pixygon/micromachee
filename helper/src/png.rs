//! A PNG encoder for exactly one job: a 240×160 indexed image with 8 colours.
//!
//! Written by hand rather than pulled in, because the whole of it is smaller
//! than the dependency would be. Two tricks keep it that way:
//!
//!   * **Bit depth 4.** Eight colours need three bits, and PNG offers 1, 2, 4.
//!     Four bits packs two pixels per byte, so a frame is 8 KB rather than 16.
//!   * **Stored deflate.** A zlib stream may contain uncompressed blocks. That
//!     removes the compressor entirely and costs a few percent of size on a
//!     pipe that is local anyway.

/// PNG wants the palette as flat RGB triples.
pub fn encode(width: u32, height: u32, palette: &[(u8, u8, u8)], indices: &[u8]) -> Vec<u8> {
    assert!(palette.len() <= 16, "bit depth 4 holds 16 entries");
    assert_eq!(indices.len(), (width * height) as usize);

    let mut out = Vec::with_capacity(indices.len() / 2 + 512);
    out.extend_from_slice(&[0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a]);

    let mut ihdr = Vec::new();
    ihdr.extend_from_slice(&width.to_be_bytes());
    ihdr.extend_from_slice(&height.to_be_bytes());
    ihdr.push(4); // bit depth
    ihdr.push(3); // colour type 3 — indexed
    ihdr.extend_from_slice(&[0, 0, 0]); // deflate, adaptive filtering, no interlace
    chunk(&mut out, b"IHDR", &ihdr);

    let mut plte = Vec::with_capacity(palette.len() * 3);
    for (r, g, b) in palette {
        plte.extend_from_slice(&[*r, *g, *b]);
    }
    chunk(&mut out, b"PLTE", &plte);

    // Scanlines: one filter byte (0 = none) then two pixels per byte.
    let row_bytes = (width as usize + 1) / 2;
    let mut raw = Vec::with_capacity(height as usize * (row_bytes + 1));
    for y in 0..height as usize {
        raw.push(0);
        let row = &indices[y * width as usize..(y + 1) * width as usize];
        for pair in row.chunks(2) {
            let hi = pair[0] & 0x0f;
            let lo = pair.get(1).copied().unwrap_or(0) & 0x0f;
            raw.push((hi << 4) | lo);
        }
    }
    chunk(&mut out, b"IDAT", &zlib_stored(&raw));
    chunk(&mut out, b"IEND", &[]);
    out
}

fn chunk(out: &mut Vec<u8>, kind: &[u8; 4], data: &[u8]) {
    out.extend_from_slice(&(data.len() as u32).to_be_bytes());
    out.extend_from_slice(kind);
    out.extend_from_slice(data);
    let mut crc_input = Vec::with_capacity(4 + data.len());
    crc_input.extend_from_slice(kind);
    crc_input.extend_from_slice(data);
    out.extend_from_slice(&crc32(&crc_input).to_be_bytes());
}

/// A zlib stream made only of stored (uncompressed) deflate blocks.
fn zlib_stored(data: &[u8]) -> Vec<u8> {
    let mut out = vec![0x78, 0x01]; // deflate, 32K window, no preset dict
    let mut rest = data;
    loop {
        let take = rest.len().min(0xffff);
        let last = if take == rest.len() { 1u8 } else { 0u8 };
        out.push(last); // BFINAL, BTYPE=00
        out.extend_from_slice(&(take as u16).to_le_bytes());
        out.extend_from_slice(&(!(take as u16)).to_le_bytes());
        out.extend_from_slice(&rest[..take]);
        rest = &rest[take..];
        if last == 1 {
            break;
        }
    }
    out.extend_from_slice(&adler32(data).to_be_bytes());
    out
}

fn crc32(data: &[u8]) -> u32 {
    let mut crc = 0xffff_ffffu32;
    for &b in data {
        crc ^= b as u32;
        for _ in 0..8 {
            crc = if crc & 1 != 0 { (crc >> 1) ^ 0xedb8_8320 } else { crc >> 1 };
        }
    }
    !crc
}

fn adler32(data: &[u8]) -> u32 {
    let (mut a, mut b) = (1u32, 0u32);
    for &byte in data {
        a = (a + byte as u32) % 65521;
        b = (b + a) % 65521;
    }
    (b << 16) | a
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pal() -> Vec<(u8, u8, u8)> {
        (0..8).map(|i| (i * 8, i * 8, i * 8)).collect()
    }

    #[test]
    fn it_is_a_png() {
        let png = encode(4, 2, &pal(), &[0, 1, 2, 3, 4, 5, 6, 7]);
        assert_eq!(&png[..8], &[0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a]);
        assert_eq!(&png[12..16], b"IHDR");
        assert!(png.ends_with(&[0xae, 0x42, 0x60, 0x82]), "IEND CRC terminates a PNG");
    }

    #[test]
    fn every_chunk_carries_a_correct_crc() {
        // A wrong CRC is the failure that renders as a blank widget with no
        // error anywhere, so it is worth checking rather than assuming.
        let png = encode(8, 8, &pal(), &vec![3u8; 64]);
        let mut i = 8;
        let mut kinds = Vec::new();
        while i + 12 <= png.len() {
            let len = u32::from_be_bytes(png[i..i + 4].try_into().unwrap()) as usize;
            let kind = &png[i + 4..i + 8];
            let body = &png[i + 4..i + 8 + len];
            let want = u32::from_be_bytes(png[i + 8 + len..i + 12 + len].try_into().unwrap());
            assert_eq!(crc32(body), want, "bad CRC on {}", String::from_utf8_lossy(kind));
            kinds.push(String::from_utf8_lossy(kind).to_string());
            i += 12 + len;
        }
        assert_eq!(kinds, vec!["IHDR", "PLTE", "IDAT", "IEND"]);
    }

    #[test]
    fn a_frame_stays_small_enough_to_stream() {
        // 30 of these a second go down a pipe as base64; the size is the
        // budget, so it gets an assertion rather than a hope.
        let png = encode(240, 160, &pal(), &vec![0u8; 240 * 160]);
        assert!(png.len() < 21_000, "frame was {} bytes", png.len());
    }

    #[test]
    fn two_pixels_share_a_byte() {
        let png = encode(2, 1, &pal(), &[7, 1]);
        // …0x71 appears in the stored block, high nibble first.
        assert!(png.windows(1).any(|w| w[0] == 0x71), "pixels are packed high-nibble-first");
    }

    #[test]
    fn known_checksums() {
        assert_eq!(crc32(b"IEND"), 0xae42_6082);
        assert_eq!(adler32(b"abc"), 0x024d_0127);
    }
}
