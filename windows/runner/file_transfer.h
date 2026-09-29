#ifndef RUNNER_FILE_TRANSFER_H_
#define RUNNER_FILE_TRANSFER_H_
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <memory>
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> CreateFileTransferChannel(flutter::BinaryMessenger* messenger);
#endif
