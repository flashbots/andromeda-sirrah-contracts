#!/bin/bash
dd if=/dev/urandom bs=1 count=32 2> /dev/null | xxd -p -c64 
