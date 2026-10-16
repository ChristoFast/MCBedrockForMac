// d3d12probe: checks whether Direct3D 12 (and 11) work under Wine on macOS.
//
// Minecraft Bedrock for Windows renders with D3D12, so this is the first thing
// that has to work. It lists the GPUs Wine reports, creates a D3D12 device, prints
// the feature levels and shader model the game cares about, then opens a window
// and renders a few seconds of cleared frames through a real swap chain.
//
// Exit codes: 0 = all good, 1 = DXGI failed, 2 = no D3D12 device,
//             3 = window/swap chain failed, 4 = rendering failed.
//
// Build (from Linux): tools/d3d12probe/build.sh

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11.h>
#include <d3d12.h>
#include <dxgi1_4.h>
#include <cstdio>
#include <cmath>

// Older MinGW headers lack 12_2.
static const D3D_FEATURE_LEVEL FL_12_2 = (D3D_FEATURE_LEVEL)0xc200;

static void say(const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
    fflush(stdout);
}

static const char* fl_name(D3D_FEATURE_LEVEL fl) {
    static char buf[16];
    if (fl == FL_12_2) return "12_2";
    snprintf(buf, sizeof buf, "%x_%x", (unsigned)fl >> 12, ((unsigned)fl >> 8) & 0xf);
    return buf;
}

static LRESULT CALLBACK wndproc(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(h, m, w, l);
}

template <class T> static void release(T*& p) { if (p) { p->Release(); p = nullptr; } }

int main() {
    say("== d3d12probe ==\n");

    // --- DXGI: which GPUs does Wine expose? -------------------------------
    IDXGIFactory4* factory = nullptr;
    HRESULT hr = CreateDXGIFactory1(IID_PPV_ARGS(&factory));
    if (FAILED(hr)) { say("FAIL dxgi: CreateDXGIFactory1 hr=0x%08lx\n", hr); return 1; }

    IDXGIAdapter1* adapter = nullptr;
    for (UINT i = 0; factory->EnumAdapters1(i, &adapter) != DXGI_ERROR_NOT_FOUND; ++i) {
        DXGI_ADAPTER_DESC1 d;
        adapter->GetDesc1(&d);
        say("adapter %u: %ls | vendor 0x%04x | video memory %llu MB%s\n", i, d.Description,
            d.VendorId, (unsigned long long)(d.DedicatedVideoMemory >> 20),
            (d.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) ? " | SOFTWARE" : "");
        release(adapter);
    }

    // --- D3D11 (some Bedrock paths and many helpers still use it) ---------
    {
        ID3D11Device* dev11 = nullptr;
        D3D_FEATURE_LEVEL got11 = (D3D_FEATURE_LEVEL)0;
        hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, nullptr, 0,
                               D3D11_SDK_VERSION, &dev11, &got11, nullptr);
        if (SUCCEEDED(hr)) say("PASS d3d11: device at feature level %s\n", fl_name(got11));
        else say("WARN d3d11: D3D11CreateDevice hr=0x%08lx\n", hr);
        release(dev11);
    }

    // --- D3D12 device -----------------------------------------------------
    ID3D12Device* dev = nullptr;
    hr = D3D12CreateDevice(nullptr, D3D_FEATURE_LEVEL_11_0, IID_PPV_ARGS(&dev));
    if (FAILED(hr)) { say("FAIL d3d12: D3D12CreateDevice hr=0x%08lx\n", hr); return 2; }
    say("PASS d3d12: device created\n");

    D3D_FEATURE_LEVEL levels[] = { D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_11_1,
                                   D3D_FEATURE_LEVEL_12_0, D3D_FEATURE_LEVEL_12_1,
                                   FL_12_2 };
    D3D12_FEATURE_DATA_FEATURE_LEVELS fls = { 5, levels, D3D_FEATURE_LEVEL_11_0 };
    if (SUCCEEDED(dev->CheckFeatureSupport(D3D12_FEATURE_FEATURE_LEVELS, &fls, sizeof fls)))
        say("info d3d12: max feature level %s\n", fl_name(fls.MaxSupportedFeatureLevel));

    D3D_SHADER_MODEL models[] = { (D3D_SHADER_MODEL)0x66, (D3D_SHADER_MODEL)0x65,
                                  (D3D_SHADER_MODEL)0x64, (D3D_SHADER_MODEL)0x63,
                                  (D3D_SHADER_MODEL)0x62, (D3D_SHADER_MODEL)0x61,
                                  (D3D_SHADER_MODEL)0x60, (D3D_SHADER_MODEL)0x51 };
    for (D3D_SHADER_MODEL m : models) {
        D3D12_FEATURE_DATA_SHADER_MODEL sm = { m };
        if (SUCCEEDED(dev->CheckFeatureSupport(D3D12_FEATURE_SHADER_MODEL, &sm, sizeof sm))) {
            say("info d3d12: highest shader model %x.%x\n", sm.HighestShaderModel >> 4,
                sm.HighestShaderModel & 0xf);
            break;
        }
    }

    D3D12_FEATURE_DATA_D3D12_OPTIONS opts = {};
    if (SUCCEEDED(dev->CheckFeatureSupport(D3D12_FEATURE_D3D12_OPTIONS, &opts, sizeof opts)))
        say("info d3d12: resource binding tier %d, tiled resources tier %d\n",
            (int)opts.ResourceBindingTier, (int)opts.TiledResourcesTier);

    // --- Window + swap chain ----------------------------------------------
    const UINT W = 640, H = 360, BUFFERS = 2;
    WNDCLASSW wc = {};
    wc.lpfnWndProc = wndproc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.lpszClassName = L"d3d12probe";
    RegisterClassW(&wc);
    RECT r = { 0, 0, (LONG)W, (LONG)H };
    AdjustWindowRect(&r, WS_OVERLAPPEDWINDOW, FALSE);
    HWND hwnd = CreateWindowW(L"d3d12probe", L"MCBedrockForMac - D3D12 probe",
                              WS_OVERLAPPEDWINDOW | WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT,
                              r.right - r.left, r.bottom - r.top, nullptr, nullptr,
                              wc.hInstance, nullptr);
    if (!hwnd) { say("FAIL window: CreateWindow error %lu\n", GetLastError()); return 3; }

    ID3D12CommandQueue* queue = nullptr;
    D3D12_COMMAND_QUEUE_DESC qd = {};
    qd.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    hr = dev->CreateCommandQueue(&qd, IID_PPV_ARGS(&queue));
    if (FAILED(hr)) { say("FAIL d3d12: CreateCommandQueue hr=0x%08lx\n", hr); return 4; }

    DXGI_SWAP_CHAIN_DESC1 scd = {};
    scd.Width = W;
    scd.Height = H;
    scd.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    scd.SampleDesc.Count = 1;
    scd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    scd.BufferCount = BUFFERS;
    scd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
    IDXGISwapChain1* sc1 = nullptr;
    hr = factory->CreateSwapChainForHwnd(queue, hwnd, &scd, nullptr, nullptr, &sc1);
    if (FAILED(hr)) { say("FAIL swapchain: CreateSwapChainForHwnd hr=0x%08lx\n", hr); return 3; }
    IDXGISwapChain3* sc = nullptr;
    sc1->QueryInterface(IID_PPV_ARGS(&sc));
    release(sc1);
    say("PASS swapchain: %ux%u flip-discard\n", W, H);

    ID3D12DescriptorHeap* rtvHeap = nullptr;
    D3D12_DESCRIPTOR_HEAP_DESC hd = {};
    hd.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
    hd.NumDescriptors = BUFFERS;
    dev->CreateDescriptorHeap(&hd, IID_PPV_ARGS(&rtvHeap));
    UINT rtvStep = dev->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_RTV);
    D3D12_CPU_DESCRIPTOR_HANDLE rtv0 = rtvHeap->GetCPUDescriptorHandleForHeapStart();
    ID3D12Resource* targets[BUFFERS] = {};
    for (UINT i = 0; i < BUFFERS; ++i) {
        sc->GetBuffer(i, IID_PPV_ARGS(&targets[i]));
        D3D12_CPU_DESCRIPTOR_HANDLE h = { rtv0.ptr + i * rtvStep };
        dev->CreateRenderTargetView(targets[i], nullptr, h);
    }

    ID3D12CommandAllocator* alloc = nullptr;
    ID3D12GraphicsCommandList* list = nullptr;
    ID3D12Fence* fence = nullptr;
    dev->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&alloc));
    dev->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, alloc, nullptr, IID_PPV_ARGS(&list));
    list->Close();
    dev->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&fence));
    HANDLE fenceEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    UINT64 fenceValue = 0;

    // --- Render ~3 seconds of frames ---------------------------------------
    LARGE_INTEGER freq, t0, t1;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&t0);
    int frames = 0;
    bool ok = true;
    for (;;) {
        MSG msg;
        while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        QueryPerformanceCounter(&t1);
        double secs = double(t1.QuadPart - t0.QuadPart) / double(freq.QuadPart);
        if (secs > 3.0) break;

        UINT idx = sc->GetCurrentBackBufferIndex();
        alloc->Reset();
        list->Reset(alloc, nullptr);

        D3D12_RESOURCE_BARRIER b = {};
        b.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
        b.Transition.pResource = targets[idx];
        b.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
        b.Transition.StateBefore = D3D12_RESOURCE_STATE_PRESENT;
        b.Transition.StateAfter = D3D12_RESOURCE_STATE_RENDER_TARGET;
        list->ResourceBarrier(1, &b);

        // Grass green, pulsing, so it's obvious frames are really being presented.
        float pulse = 0.5f + 0.5f * (float)sin(secs * 4.0);
        float color[4] = { 0.20f, 0.45f + 0.35f * pulse, 0.15f, 1.0f };
        D3D12_CPU_DESCRIPTOR_HANDLE h = { rtv0.ptr + idx * rtvStep };
        list->ClearRenderTargetView(h, color, 0, nullptr);

        b.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET;
        b.Transition.StateAfter = D3D12_RESOURCE_STATE_PRESENT;
        list->ResourceBarrier(1, &b);
        list->Close();
        ID3D12CommandList* lists[] = { list };
        queue->ExecuteCommandLists(1, lists);

        hr = sc->Present(1, 0);
        if (FAILED(hr)) { say("FAIL present: hr=0x%08lx\n", hr); ok = false; break; }

        queue->Signal(fence, ++fenceValue);
        if (fence->GetCompletedValue() < fenceValue) {
            fence->SetEventOnCompletion(fenceValue, fenceEvent);
            if (WaitForSingleObject(fenceEvent, 2000) != WAIT_OBJECT_0) {
                say("FAIL gpu: frame did not finish within 2 s (GPU hang?)\n");
                ok = false;
                break;
            }
        }
        ++frames;
    }

    QueryPerformanceCounter(&t1);
    double secs = double(t1.QuadPart - t0.QuadPart) / double(freq.QuadPart);
    if (ok && frames > 0)
        say("PASS render: %d frames in %.1f s (%.0f fps)\n", frames, secs, frames / secs);

    for (auto& t : targets) release(t);
    release(fence); release(list); release(alloc); release(rtvHeap);
    release(sc); release(queue); release(dev); release(factory);
    DestroyWindow(hwnd);

    say(ok && frames > 0 ? "RESULT: D3D12 works\n" : "RESULT: D3D12 rendering failed\n");
    return ok && frames > 0 ? 0 : 4;
}
