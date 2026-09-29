#pragma once
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <memory>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateLicenseStorageChannel(flutter::BinaryMessenger* messenger);
