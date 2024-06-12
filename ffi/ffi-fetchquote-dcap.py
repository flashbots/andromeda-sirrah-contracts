import json
import sys
from urllib.request import urlopen, Request
#import eth_abi
import base64
from binascii import hexlify

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: python ffi-fetchquote-dcap.py 00....00   (a 64-byte hex)')
        sys.exit(1)
    msg = sys.argv[1]
    assert len(bytes.fromhex(msg)) == 64
    url = f"https://dcap-dummy.sirrah.suave.flashbots.net/dcap/{msg}"
    req = Request(url, headers={'User-Agent' : "Magic Browser"})
    obj = urlopen(req).read()
    sys.stdout.buffer.write(obj+b'\n')
    #print("abidata:")
    #print(hexlify(abidata))
    #print("sig:")
    #print(hexlify(sig))
