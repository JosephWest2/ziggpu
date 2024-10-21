const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const c = @cImport({
    @cInclude("wgpu.h");
});

pub fn main() !void {
    const version = c.wgpuGetVersion();
    print("wgpu version: {}\n", .{version});

    const wgpu_descriptor = c.WGPUInstanceDescriptor{};
    const wgpu_instance = c.wgpuCreateInstance(&wgpu_descriptor);
    defer c.wgpuInstanceRelease(wgpu_instance);

    const adapter_request_options = c.WGPURequestAdapterOptions{ .powerPreference = c.WGPUPowerPreference_HighPerformance };
    var adapter_request_result: ?c.WGPUAdapter = null;
    c.wgpuInstanceRequestAdapter(wgpu_instance, &adapter_request_options, adapterRequestCallback, &adapter_request_result);

    const adapter = adapter_request_result orelse return error.WGPUAdapterRequestFailure;
    defer c.wgpuAdapterRelease(adapter);

    var supported_limits = c.WGPUSupportedLimits{};
    if (c.wgpuAdapterGetLimits(adapter, &supported_limits) != 1) return error.WGPUCannotGetAdapterLimits;
    print("Limits: {}\n", .{supported_limits.limits});

    var gpa = GeneralPurposeAllocator(.{}){};
    defer assert(gpa.deinit() == std.heap.Check.ok);
    const allocator = gpa.allocator();

    const feature_count = c.wgpuAdapterEnumerateFeatures(adapter, null);
    print("Feature count {}", .{feature_count});

    const feature_buffer = try allocator.alloc(c.WGPUFeatureName, feature_count);
    defer allocator.free(feature_buffer);

    _ = c.wgpuAdapterEnumerateFeatures(adapter, @ptrCast(feature_buffer));

    for (feature_buffer) |feature| {
        print("{}\n", .{feature});
    }

    var adapter_info: c.WGPUAdapterInfo = undefined;
    c.wgpuAdapterGetInfo(adapter, &adapter_info);

    print(
        \\deviceID: {}
        \\vendor: {s}
        \\description: {s}
        \\architecture: {s}
        \\device: {s}
        \\
    , .{
        adapter_info.deviceID,
        adapter_info.vendor,
        adapter_info.description,
        adapter_info.architecture,
        adapter_info.device,
    });
    
    const device_request_descriptor = c.WGPUDeviceDescriptor{ .deviceLostCallback = deviceLostCallback, .uncapturedErrorCallbackInfo = c.WGPUUncapturedErrorCallbackInfo{ .callback = deviceUncapturedErrorCallback } };
    var device_request_result: ?c.WGPUDevice = null;
    c.wgpuAdapterRequestDevice(adapter, &device_request_descriptor, deviceRequestCallback, &device_request_result);

    const device = device_request_result orelse return error.WGPUDeviceRequestFailure;

    const queue = c.wgpuDeviceGetQueue(device);
    c.wgpuQueueOnSubmittedWorkDone(queue, queueSubmittedWorkDoneCallback, null);
    defer c.wgpuQueueRelease(queue);

    const command_encoder_descriptor = c.WGPUCommandEncoderDescriptor{};
    const encoder = c.wgpuDeviceCreateCommandEncoder(device, &command_encoder_descriptor);
    defer c.wgpuCommandEncoderRelease(encoder);

    c.wgpuCommandEncoderInsertDebugMarker(encoder, "Test label");
    c.wgpuCommandEncoderInsertDebugMarker(encoder, "Test label 2");

    const command_buffer_descriptor = c.WGPUCommandBufferDescriptor{};
    const command_buffer = c.wgpuCommandEncoderFinish(encoder, &command_buffer_descriptor);
    defer c.wgpuCommandBufferRelease(command_buffer);

    c.wgpuQueueSubmit(queue, 1, &command_buffer);
    print("Command buffer submitted\n", .{});

    std.time.sleep(1000000000);

}

fn queueSubmittedWorkDoneCallback(work_done_status: c.WGPUQueueWorkDoneStatus, user_data: ?*anyopaque) callconv(.C) void {
    _ = user_data;
    print("Queued work completed with status: {}", .{work_done_status});
}

fn deviceLostCallback(reason: c.WGPUDeviceLostReason, message: [*c]const u8, user_data: ?*anyopaque) callconv(.C) void {
    _ = user_data;
    print("Device lost: reason {}", .{reason});
    print("Device lost message: {}", .{message.*});
}

fn deviceUncapturedErrorCallback(error_type: c.WGPUErrorType, message: [*c]const u8, user_data: ?*anyopaque) callconv(.C) void {
    _ = user_data;
    print("Uncaptured device error: type {}", .{error_type});
    print("Uncaptured device error message: {}", .{message.*});
}

fn deviceRequestCallback(request_status: c.WGPURequestDeviceStatus, device: c.WGPUDevice, message: [*c]const u8, user_data: ?*anyopaque) callconv(.C) void {
    const device_request_result: *?c.WGPUDevice = @alignCast(@ptrCast(user_data));
    if (request_status == c.WGPURequestDeviceStatus_Success) {
        device_request_result.* = device;
    } else {
        print("failed to get wgpu device: {}\n", .{message.*});
    }
}

fn adapterRequestCallback(request_status: c.WGPURequestAdapterStatus, adapter: c.WGPUAdapter, message: [*c]const u8, user_data: ?*anyopaque) callconv(.C) void {
    const adapter_request_result: *?c.WGPUAdapter = @alignCast(@ptrCast(user_data));
    if (request_status == c.WGPURequestAdapterStatus_Success) {
        adapter_request_result.* = adapter;
    } else {
        print("failed to get wgpu adapter: {}\n", .{message.*});
    }
}
