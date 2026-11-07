#include "file_transfer.h"
#include <windows.h>
#include <ole2.h>
#include <shobjidl.h>
#include <shlguid.h>
#include <wrl/client.h>
#include <string>

namespace {
class FileDropSource final : public IDropSource {
 public:
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** output) override {
    if (!output) return E_POINTER;
    *output = nullptr;
    if (iid == IID_IUnknown || iid == IID_IDropSource) {
      *output = static_cast<IDropSource*>(this); AddRef(); return S_OK;
    }
    return E_NOINTERFACE;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&refs_); }
  ULONG STDMETHODCALLTYPE Release() override {
    const auto count = InterlockedDecrement(&refs_);
    if (!count) delete this;
    return count;
  }
  HRESULT STDMETHODCALLTYPE QueryContinueDrag(BOOL escape, DWORD keys) override {
    if (escape) return DRAGDROP_S_CANCEL;
    return (keys & MK_LBUTTON) ? S_OK : DRAGDROP_S_DROP;
  }
  HRESULT STDMETHODCALLTYPE GiveFeedback(DWORD) override { return DRAGDROP_S_USEDEFAULTCURSORS; }
 private:
  LONG refs_ = 1;
};
std::wstring Utf16(const std::string& text) {
  const auto length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), nullptr, 0);
  if (!length) return {};
  std::wstring result(length, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), result.data(), length);
  return result;
}
}

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> CreateFileTransferChannel(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(messenger, "fly/file_transfer", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() != "copy" && call.method_name() != "drag") { result->NotImplemented(); return; }
    const auto* raw = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
    if (!raw || raw->empty() || raw->find('\0') != std::string::npos) { result->Error("invalid_path", "A local file path is required"); return; }
    const auto path = Utf16(*raw);
    const auto attributes = GetFileAttributesW(path.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_DIRECTORY)) { result->Error("missing_file", "File not found"); return; }
    const auto initialized = OleInitialize(nullptr);
    if (FAILED(initialized)) { result->Error("ole_init", "Windows file transfer could not initialize"); return; }
    HRESULT status;
    {
      Microsoft::WRL::ComPtr<IShellItem> item;
      Microsoft::WRL::ComPtr<IDataObject> data;
      status = SHCreateItemFromParsingName(path.c_str(), nullptr, IID_PPV_ARGS(&item));
      if (SUCCEEDED(status)) status = item->BindToHandler(nullptr, BHID_DataObject, IID_PPV_ARGS(&data));
      if (SUCCEEDED(status)) {
        if (call.method_name() == "copy") {
          status = OleSetClipboard(data.Get());
          if (SUCCEEDED(status)) status = OleFlushClipboard();
        } else if (!(GetAsyncKeyState(VK_LBUTTON) & 0x8000)) {
          // The platform message may arrive after a quick click has ended.
          // Starting OLE now would immediately drop the file under the cursor.
          status = DRAGDROP_S_CANCEL;
        } else {
          auto* source = new FileDropSource();
          DWORD effect = DROPEFFECT_NONE;
          // Never advertise MOVE: the managed source must remain in FlyData.
          status = DoDragDrop(data.Get(), source, DROPEFFECT_COPY, &effect);
          source->Release();
        }
      }
    }
    OleUninitialize();
    if (FAILED(status)) result->Error("transfer_failed", "Windows rejected the file transfer");
    else result->Success(flutter::EncodableValue(status != DRAGDROP_S_CANCEL));
  });
  return channel;
}
