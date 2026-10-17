const encoder = new TextEncoder();
const crcTable = Array.from({ length: 256 }, (_, value) => {
  for (let bit = 0; bit < 8; bit++) value = (value >>> 1) ^ ((value & 1) ? 0xedb88320 : 0);
  return value >>> 0;
});

function checksum(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) crc = (crc >>> 8) ^ crcTable[(crc ^ byte) & 255];
  return (crc ^ 0xffffffff) >>> 0;
}

function record(size) {
  const bytes = new Uint8Array(size);
  const view = new DataView(bytes.buffer);
  return { bytes, short: (offset, value) => view.setUint16(offset, value, true),
    long: (offset, value) => view.setUint32(offset, value, true) };
}

/** Creates a UTF-8, stored ZIP32 archive with CRC32 checksums and relative paths. */
export function createZip(files) {
  if (files.length > 65535) throw new Error('Too many files. Export a smaller selection.');
  const entries = [];
  const directory = [];
  let offset = 0;
  let directorySize = 0;
  for (const file of files) {
    const name = encoder.encode(file.path);
    const bytes = typeof file.content === 'string' ? encoder.encode(file.content) : file.content;
    if (bytes.length + offset + name.length + 30 > 0xffffffff) throw new Error('Archive exceeds ZIP32 limits. Export a smaller selection.');
    const crc = checksum(bytes);
    const header = record(30);
    header.long(0, 0x04034b50); header.short(4, 20); header.short(6, 0x0800);
    header.short(12, 33); header.long(14, crc); header.long(18, bytes.length);
    header.long(22, bytes.length); header.short(26, name.length);
    entries.push(header.bytes, name, bytes);
    const central = record(46);
    central.long(0, 0x02014b50); central.short(4, 20); central.short(6, 20);
    central.short(8, 0x0800); central.short(14, 33); central.long(16, crc);
    central.long(20, bytes.length); central.long(24, bytes.length);
    central.short(28, name.length); central.long(42, offset);
    directory.push(central.bytes, name);
    directorySize += 46 + name.length;
    offset += 30 + name.length + bytes.length;
  }
  if (offset + directorySize > 0xffffffff) throw new Error('Archive exceeds ZIP32 limits. Export a smaller selection.');
  const end = record(22);
  end.long(0, 0x06054b50); end.short(8, files.length); end.short(10, files.length);
  end.long(12, directorySize); end.long(16, offset);
  return new Blob([...entries, ...directory, end.bytes], { type: 'application/zip' });
}
