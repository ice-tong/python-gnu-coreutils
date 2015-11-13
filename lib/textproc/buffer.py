class FifoBuffer:
    def __init__(self, size, creator):
        self.size = abs(size)
        self.creator = creator
        self.buffer = self._create_buffer()

    def filter(self, data):
        if self.size == 0:
            res = data
        else:
            self.buffer.extend(data)
            if len(self.buffer) > self.size:
                res = self.buffer[:-self.size]
                self.buffer[:-self.size] = self._create_buffer()
            else:
                res = self._create_buffer()
        return res

    def get_buffer(self):
        return self.buffer[:self.size]

    def _create_buffer(self):
            return self.creator()
