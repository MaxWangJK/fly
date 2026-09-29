#include "license_storage.h"
#include <windows.h>
#include <wincrypt.h>
#include <string>
#include <vector>

namespace {
constexpr wchar_t kPath[] = L"Software\\Fly\\LocalLicense";
constexpr wchar_t kValue[] = L"ProtectedState";
using Value = flutter::EncodableValue;
}

std::unique_ptr<flutter::MethodChannel<Value>>
CreateLicenseStorageChannel(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "fly/license_storage", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() == "machine") {
      wchar_t guid[256] = {};
      DWORD bytes = sizeof(guid);
      const auto status = RegGetValueW(HKEY_LOCAL_MACHINE,
          L"SOFTWARE\\Microsoft\\Cryptography", L"MachineGuid",
          RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY, nullptr, guid, &bytes);
      if (status != ERROR_SUCCESS) {
        result->Error("machine", "Cannot read machine identity"); return;
      }
      const int size = WideCharToMultiByte(CP_UTF8, 0, guid, -1, nullptr, 0, nullptr, nullptr);
      if (size <= 1) { result->Error("machine", "Empty machine identity"); return; }
      std::string text(static_cast<size_t>(size), '\0');
      WideCharToMultiByte(CP_UTF8, 0, guid, -1, text.data(), size, nullptr, nullptr);
      text.pop_back();
      result->Success(Value(text)); return;
    }
    if (call.method_name() == "read") {
      DWORD bytes = 0;
      auto status = RegGetValueW(HKEY_CURRENT_USER, kPath, kValue,
          RRF_RT_REG_BINARY, nullptr, nullptr, &bytes);
      if (status == ERROR_FILE_NOT_FOUND) { result->Success(); return; }
      if (status != ERROR_SUCCESS || bytes == 0 || bytes > 65536) {
        result->Error("storage", "Cannot read protected license state"); return;
      }
      std::vector<BYTE> data(bytes);
      status = RegGetValueW(HKEY_CURRENT_USER, kPath, kValue,
          RRF_RT_REG_BINARY, nullptr, data.data(), &bytes);
      DATA_BLOB input{bytes, data.data()}, output{};
      if (status != ERROR_SUCCESS || !CryptUnprotectData(&input, nullptr, nullptr,
          nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output)) {
        result->Error("storage", "License state is damaged or belongs to another user"); return;
      }
      const std::string text(reinterpret_cast<char*>(output.pbData), output.cbData);
      LocalFree(output.pbData);
      result->Success(Value(text)); return;
    }
    if (call.method_name() == "write") {
      const auto* text = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
      if (!text || text->empty() || text->size() > 32768) {
        result->Error("input", "Invalid license state"); return;
      }
      DATA_BLOB input{static_cast<DWORD>(text->size()),
          reinterpret_cast<BYTE*>(const_cast<char*>(text->data()))}, output{};
      if (!CryptProtectData(&input, L"Fly offline license", nullptr, nullptr,
          nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output)) {
        result->Error("storage", "Cannot protect license state"); return;
      }
      HKEY key = nullptr;
      auto status = RegCreateKeyExW(HKEY_CURRENT_USER, kPath, 0, nullptr, 0,
          KEY_SET_VALUE, nullptr, &key, nullptr);
      if (status == ERROR_SUCCESS) {
        status = RegSetValueExW(key, kValue, 0, REG_BINARY, output.pbData, output.cbData);
        RegCloseKey(key);
      }
      LocalFree(output.pbData);
      if (status != ERROR_SUCCESS) { result->Error("storage", "Cannot save license state"); return; }
      result->Success(); return;
    }
    result->NotImplemented();
  });
  return channel;
}
