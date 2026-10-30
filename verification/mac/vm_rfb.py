import hashlib
import os
import socket
import struct
import subprocess
import time
import zlib

KEYS = {
    'return': 0xff0d, 'tab': 0xff09, 'escape': 0xff1b, 'left': 0xff51, 'up': 0xff52, 'right': 0xff53,
    'down': 0xff54, 'shift': 0xffe1, 'control': 0xffe3, 'option': 0xffe9, 'command': 0xffeb, 'space': 0x20,
}


def des_key(password):
    # VNC authentication uses only the first 8 bytes, with each byte's bits mirrored.
    return bytes(int(f'{byte:08b}'[::-1], 2) for byte in password.encode()[:8].ljust(8, b'\0'))


def respond(challenge, password):
    return subprocess.run(['/usr/bin/openssl', 'enc', '-des-ecb', '-nopad', '-K', des_key(password).hex()],
                          input=challenge, capture_output=True, check=True).stdout[:16]


def ard_credentials(username, password, prime, generator, server_key, private=None):
    size = len(prime)
    modulus = int.from_bytes(prime, 'big')
    private = private or int.from_bytes(os.urandom(size), 'big') % modulus
    public = pow(int.from_bytes(generator, 'big'), private, modulus).to_bytes(size, 'big')
    shared = pow(int.from_bytes(server_key, 'big'), private, modulus).to_bytes(size, 'big')
    plain = b''.join(value.encode()[:63].ljust(64, b'\0') for value in (username, password))
    secret = subprocess.run(['/usr/bin/openssl', 'enc', '-aes-128-ecb', '-nopad', '-K', hashlib.md5(shared).hexdigest()],
                            input=plain, capture_output=True, check=True).stdout
    return secret + public


def keysym(character):
    return KEYS[character] if character in KEYS else ord(character)


def png(width, height, pixels):
    rows = b''.join(b'\0' + bytes(pixels[(y * width + x) * 4 + c] for x in range(width) for c in (2, 1, 0))
                    for y in range(height))

    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))

    header = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + chunk(b'IDAT', zlib.compress(rows, 6)) + chunk(b'IEND', b'')


class RFB:
    def __init__(self, port, password, host='127.0.0.1', username=None):
        self.socket = socket.create_connection((host, port), timeout=30)
        version = self.exact(12)
        self.socket.sendall(version if version == b'RFB 003.889\n' else b'RFB 003.008\n')
        offered = self.exact(self.exact(1)[0])
        if username:
            if 30 not in offered:
                raise SystemExit('the VNC server does not offer macOS account login')
            self.socket.sendall(b'\x1e')
            generator, size = self.exact(2), struct.unpack('>H', self.exact(2))[0]
            prime, server_key = self.exact(size), self.exact(size)
            self.socket.sendall(ard_credentials(username, password, prime, generator, server_key))
        else:
            if 2 not in offered:
                raise SystemExit('the VNC server does not offer password authentication')
            self.socket.sendall(b'\x02')
            self.socket.sendall(respond(self.exact(16), password))
        if struct.unpack('>I', self.exact(4))[0]:
            raise SystemExit('VNC authentication failed')
        self.socket.sendall(b'\x01')
        self.width, self.height = struct.unpack('>HH', self.exact(4))
        self.exact(16)
        self.exact(struct.unpack('>I', self.exact(4))[0])
        self.socket.sendall(struct.pack('>BxxxBBBBHHHBBBxxx', 0, 32, 24, 0, 1, 255, 255, 255, 16, 8, 0))
        # Virtualization.framework's server drops clients that do not accept desktop resizes.
        self.socket.sendall(struct.pack('>BxHiii', 2, 3, 0, -223, -308))
        self.pixels = bytearray(self.width * self.height * 4)

    def exact(self, count):
        data = b''
        while len(data) < count:
            chunk = self.socket.recv(count - len(data))
            if not chunk:
                raise SystemExit('the VNC server closed the connection')
            data += chunk
        return data

    def capture(self, path=None):
        self.socket.sendall(struct.pack('>BBHHHH', 3, 0, 0, 0, self.width, self.height))
        while True:
            kind = self.exact(1)[0]
            if kind == 0:
                break
            if kind == 2:
                continue
            if kind == 3:
                self.exact(3)
                self.exact(struct.unpack('>I', self.exact(4))[0])
                continue
            raise SystemExit(f'unexpected VNC message {kind}')
        self.exact(1)
        for _ in range(struct.unpack('>H', self.exact(2))[0]):
            x, y, width, height, encoding = struct.unpack('>HHHHi', self.exact(12))
            if encoding in (-223, -308):
                if encoding == -308:
                    screens = self.exact(4)[0]
                    self.exact(screens * 16)
                self.width, self.height = width, height
                self.pixels = bytearray(width * height * 4)
                continue
            data = self.exact(width * height * 4)
            for row in range(height):
                start = ((y + row) * self.width + x) * 4
                self.pixels[start:start + width * 4] = data[row * width * 4:(row + 1) * width * 4]
        if path:
            path.write_bytes(png(self.width, self.height, self.pixels))
        return self

    def key(self, name, modifiers=()):
        for modifier in modifiers:
            self.socket.sendall(struct.pack('>BBxxI', 4, 1, KEYS[modifier]))
        symbol = keysym(name)
        self.socket.sendall(struct.pack('>BBxxI', 4, 1, symbol))
        time.sleep(0.05)
        self.socket.sendall(struct.pack('>BBxxI', 4, 0, symbol))
        for modifier in reversed(modifiers):
            self.socket.sendall(struct.pack('>BBxxI', 4, 0, KEYS[modifier]))
        time.sleep(0.1)
        return self

    def click(self, x, y):
        for mask in (0, 1, 0):
            self.socket.sendall(struct.pack('>BBHH', 5, mask, x, y))
            time.sleep(0.15)
        return self

    def type(self, text):
        for character in text:
            self.key(character)
        return self

    def close(self):
        self.socket.close()
