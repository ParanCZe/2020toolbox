#include <windows.h>
#include <filesystem>
#include <iostream>
#include <string>

#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Printing3D.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>

using namespace winrt;
using namespace Windows::Graphics::Printing3D;
using namespace Windows::Storage;
using namespace Windows::Storage::Streams;

static std::wstring absolute_path(const wchar_t* p)
{
    return std::filesystem::absolute(std::filesystem::path(p)).wstring();
}

int wmain(int argc, wchar_t** argv)
{
    if (argc != 3) {
        std::wcerr << L"Usage: Win3DRepair.exe input.3mf output.3mf\n";
        return 2;
    }
    try {
        winrt::init_apartment(winrt::apartment_type::multi_threaded);

        const std::filesystem::path inPath = absolute_path(argv[1]);
        const std::filesystem::path outPath = absolute_path(argv[2]);

        auto inFile = StorageFile::GetFileFromPathAsync(inPath.wstring()).get();
        auto inStream = inFile.OpenAsync(FileAccessMode::Read).get();

        Printing3D3MFPackage package;
        auto model = package.LoadModelFromPackageAsync(inStream).get();
        model.RepairAsync().get();
        package.SaveModelToPackageAsync(model).get();
        auto repairedStream = package.SaveAsync().get();
        repairedStream.Seek(0);

        auto outFolder = StorageFolder::GetFolderFromPathAsync(outPath.parent_path().wstring()).get();
        auto outFile = outFolder.CreateFileAsync(outPath.filename().wstring(), CreationCollisionOption::ReplaceExisting).get();
        auto outStream = outFile.OpenAsync(FileAccessMode::ReadWrite).get();
        outStream.Seek(0);
        RandomAccessStream::CopyAsync(repairedStream, outStream).get();
        outStream.FlushAsync().get();

        std::wcout << L"WINDOWS_REPAIR_OK\n";
        return 0;
    }
    catch (winrt::hresult_error const& e) {
        std::wcerr << L"WinRT error 0x" << std::hex << static_cast<uint32_t>(e.code()) << L": " << e.message().c_str() << L"\n";
        return 10;
    }
    catch (std::exception const& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 11;
    }
    catch (...) {
        std::wcerr << L"Unknown Win3DRepair error.\n";
        return 12;
    }
}
