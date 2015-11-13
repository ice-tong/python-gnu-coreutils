bufsize = 4096

def read_data(src, is_line_mode, bs):
    default_line_buffer = 256
    default_byte_buffer = 1048576
    if is_line_mode:
        bs = min(bs, default_line_buffer)
        data = src.readlines(bs)
    else:
        bs = min(bs, default_byte_buffer)
        data = src.read(bs)
    return data

def write_out(dst, data, is_line_mode):
    if is_line_mode:
        for line in data:
            dst.write(line)
    else:
        dst.write(data)

def copy(srcPath, dstPath, bufsize=bufsize):
    srcFile = open(srcPath, 'rb')
    dstFile = open(dstPath, 'wb')
    while True:
        data = srcFile.read(bufsize)
        if not data: break
        dstFile.write(data)
    srcFile.close()
    dstFile.close()

