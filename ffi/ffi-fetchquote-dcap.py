import json
import sys
import urllib.request
import eth_abi
import base64
from binascii import hexlify

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: python ffi-fetchquote-dcap.py 00....00   (a 64-byte hex)')
        sys.exit(1)
    msg = sys.argv[1]
    assert len(bytes.fromhex(msg)) == 64
    obj = urllib.request.urlopen(f"http://dummyattest.ln.soc1024.com/dcap/{msg}").read()

    lines = obj.split(b'\n')
    
    sys.stdout.buffer.write(lines[-1]+b'\n')
    #print("abidata:")
    #print(hexlify(abidata))
    #print("sig:")
    #print(hexlify(sig))
