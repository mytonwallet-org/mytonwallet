package org.mytonwallet.app_air.ledger.usb;

import java.io.ByteArrayOutputStream;

public class LedgerUSBHelpers {

    private static final int TAG_APDU = 0x05;

    public static byte[] wrapCommandAPDU(int channel, byte[] command, int packetSize) throws Exception {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        if (packetSize < 3) {
            throw new Exception("Can't handle Ledger framing with less than 3 bytes for the report");
        }
        int sequenceIdx = 0;
        int offset = 0;
        output.write(channel >> 8);
        output.write(channel);
        output.write(TAG_APDU);
        output.write(sequenceIdx >> 8);
        output.write(sequenceIdx);
        sequenceIdx++;
        output.write(command.length >> 8);
        output.write(command.length);
        int blockSize = (Math.min(command.length, packetSize - 7));
        output.write(command, offset, blockSize);
        offset += blockSize;
        while (offset != command.length) {
            output.write(channel >> 8);
            output.write(channel);
            output.write(TAG_APDU);
            output.write(sequenceIdx >> 8);
            output.write(sequenceIdx);
            sequenceIdx++;
            blockSize = (Math.min(command.length - offset, packetSize - 5));
            output.write(command, offset, blockSize);
            offset += blockSize;
        }
        if ((output.size() % packetSize) != 0) {
            byte[] padding = new byte[packetSize - (output.size() % packetSize)];
            output.write(padding, 0, padding.length);
        }
        return output.toByteArray();
    }

    public static byte[] unwrapResponseAPDU(int channel, byte[] data, int packetSize) throws Exception {
        ByteArrayOutputStream response = new ByteArrayOutputStream();
        int offset = 0;
        int responseLength;
        int sequenceIdx = 0;
        if ((data == null) || (data.length < 7 + 5)) {
            return null;
        }
        if (data[offset++] != (channel >> 8)) {
            throw new Exception("Invalid channel");
        }
        if (data[offset++] != (channel & 0xff)) {
            throw new Exception("Invalid channel");
        }
        if (data[offset++] != TAG_APDU) {
            throw new Exception("Invalid tag");
        }
        if (data[offset++] != 0x00) {
            throw new Exception("Invalid sequence");
        }
        if (data[offset++] != 0x00) {
            throw new Exception("Invalid sequence");
        }
        responseLength = ((data[offset++] & 0xff) << 8);
        responseLength |= (data[offset++] & 0xff);
        if (data.length < 7 + responseLength) {
            return null;
        }
        int blockSize = (Math.min(responseLength, packetSize - 7));
        response.write(data, offset, blockSize);
        offset += blockSize;
        while (response.size() != responseLength) {
            sequenceIdx++;
            if (offset == data.length) {
                return null;
            }
            if (data[offset++] != (channel >> 8)) {
                throw new Exception("Invalid channel");
            }
            if (data[offset++] != (channel & 0xff)) {
                throw new Exception("Invalid channel");
            }
            if (data[offset++] != TAG_APDU) {
                throw new Exception("Invalid tag");
            }
            if (data[offset++] != (sequenceIdx >> 8)) {
                throw new Exception("Invalid sequence");
            }
            if (data[offset++] != (sequenceIdx & 0xff)) {
                throw new Exception("Invalid sequence");
            }
            blockSize = (Math.min(responseLength - response.size(), packetSize - 5));
            if (blockSize > data.length - offset) {
                return null;
            }
            response.write(data, offset, blockSize);
            offset += blockSize;
        }
        return response.toByteArray();
    }

}
