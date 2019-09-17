var io = require("socket.io");

if (io.version === "0.9.16") {
  console.log("patching socket.io hybi-16 transport frame prototype");
  var transports = require("socket.io/lib/transports/websocket/hybi-16.js");
  transports.prototype.frame = patchedFrameHandler;
  // file hybi-07-12 has the same problem but no browsers are using that protocol now
}

function patchedFrameHandler(opcode, str) {
  var dataBuffer = new Buffer(str),
    dataLength = dataBuffer.length,
    startOffset = 2,
    secondByte = dataLength;
  if (dataLength === 65536) {
    console.log("fixing invalid frame length in socket.io");
  }
  if (dataLength > 65535) {
    // original code had > 65536
    startOffset = 10;
    secondByte = 127;
  } else if (dataLength > 125) {
    startOffset = 4;
    secondByte = 126;
  }
  var outputBuffer = new Buffer(dataLength + startOffset);
  outputBuffer[0] = opcode;
  outputBuffer[1] = secondByte;
  dataBuffer.copy(outputBuffer, startOffset);
  switch (secondByte) {
    case 126:
      outputBuffer[2] = dataLength >>> 8;
      outputBuffer[3] = dataLength % 256;
      break;
    case 127:
      var l = dataLength;
      for (var i = 1; i <= 8; ++i) {
        outputBuffer[startOffset - i] = l & 0xff;
        l >>>= 8;
      }
  }
  return outputBuffer;
}
