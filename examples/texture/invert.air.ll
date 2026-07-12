; examples/texture/invert.air.ll — the `invert` texture kernel, hand-authored
; in AIR pending compiler texture-type support (see docs/textures.md). Uses
; opaque `ptr addrspace(1)` textures, which the driver accepts via the
; air.texture metadata. Assembled by examples/texture/build.sh.
; ModuleID = '/tmp/tex.metal'
source_filename = "/tmp/tex.metal"
target datalayout = "e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32"
target triple = "air64_v28-apple-macosx26.0.0"

%struct._texture_2d_t = type opaque
%struct._sampler_t = type opaque

; Function Attrs: mustprogress nounwind willreturn
define void @invert(ptr addrspace(1) nocapture readonly %0, ptr addrspace(1) %1, <2 x i32> %2) local_unnamed_addr #0 {
  %4 = tail call ptr addrspace(2) @air.get_read_sampler() #4
  %5 = tail call { <4 x float>, i8 } @air.read_texture_2d.v4f32(ptr addrspace(1) nocapture readonly %0, ptr addrspace(2) %4, <2 x i32> %2, <2 x i32> zeroinitializer, i32 0, i32 1) #5
  %6 = extractvalue { <4 x float>, i8 } %5, 0
  %7 = shufflevector <4 x float> %6, <4 x float> poison, <3 x i32> <i32 0, i32 1, i32 2>
  %8 = fsub fast <3 x float> <float 1.000000e+00, float 1.000000e+00, float 1.000000e+00>, %7
  %9 = shufflevector <3 x float> %8, <3 x float> poison, <4 x i32> <i32 0, i32 1, i32 2, i32 undef>
  %10 = shufflevector <4 x float> %9, <4 x float> %6, <4 x i32> <i32 0, i32 1, i32 2, i32 7>
  tail call void @air.write_texture_2d.v4f32(ptr addrspace(1) nocapture %1, <2 x i32> %2, <4 x float> %10, i32 0, i32 2) #6, !alias.scope !22
  ret void
}

; Function Attrs: inaccessiblememonly mustprogress nofree nounwind readonly willreturn
declare ptr addrspace(2) @air.get_read_sampler() local_unnamed_addr #1

; Function Attrs: argmemonly mustprogress nofree nounwind readonly willreturn
declare { <4 x float>, i8 } @air.read_texture_2d.v4f32(ptr addrspace(1) nocapture readonly, ptr addrspace(2), <2 x i32>, <2 x i32>, i32, i32) local_unnamed_addr #2

; Function Attrs: argmemonly mustprogress nounwind willreturn
declare void @air.write_texture_2d.v4f32(ptr addrspace(1) nocapture, <2 x i32>, <4 x float>, i32, i32) local_unnamed_addr #3

attributes #0 = { mustprogress nounwind willreturn "approx-func-fp-math"="true" "frame-pointer"="all" "min-legal-vector-width"="128" "no-builtins" "no-infs-fp-math"="true" "no-nans-fp-math"="true" "no-signed-zeros-fp-math"="true" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "unsafe-fp-math"="true" }
attributes #1 = { inaccessiblememonly mustprogress nofree nounwind readonly willreturn }
attributes #2 = { argmemonly mustprogress nofree nounwind readonly willreturn }
attributes #3 = { argmemonly mustprogress nounwind willreturn }
attributes #4 = { inaccessiblememonly nounwind readonly willreturn }
attributes #5 = { argmemonly nounwind readonly willreturn }
attributes #6 = { argmemonly nounwind willreturn }

!llvm.module.flags = !{!0, !1, !2, !3, !4, !5, !6, !7, !8}
!air.kernel = !{!9}
!air.compile_options = !{!15, !16, !17}
!llvm.ident = !{!18}
!air.version = !{!19}
!air.language_version = !{!20}
!air.source_file_name = !{!21}

!0 = !{i32 2, !"SDK Version", [2 x i32] [i32 26, i32 4]}
!1 = !{i32 1, !"wchar_size", i32 4}
!2 = !{i32 7, !"frame-pointer", i32 2}
!3 = !{i32 7, !"air.max_device_buffers", i32 31}
!4 = !{i32 7, !"air.max_constant_buffers", i32 31}
!5 = !{i32 7, !"air.max_threadgroup_buffers", i32 31}
!6 = !{i32 7, !"air.max_textures", i32 128}
!7 = !{i32 7, !"air.max_read_write_textures", i32 8}
!8 = !{i32 7, !"air.max_samplers", i32 16}
!9 = !{void (ptr addrspace(1), ptr addrspace(1), <2 x i32>)* @invert, !10, !11}
!10 = !{}
!11 = !{!12, !13, !14}
!12 = !{i32 0, !"air.texture", !"air.location_index", i32 0, i32 1, !"air.read", !"air.arg_type_name", !"texture2d<float, read>", !"air.arg_name", !"src"}
!13 = !{i32 1, !"air.texture", !"air.location_index", i32 1, i32 1, !"air.write", !"air.arg_type_name", !"texture2d<float, write>", !"air.arg_name", !"dst"}
!14 = !{i32 2, !"air.thread_position_in_grid", !"air.arg_type_name", !"uint2", !"air.arg_name", !"gid"}
!15 = !{!"air.compile.denorms_disable"}
!16 = !{!"air.compile.fast_math_enable"}
!17 = !{!"air.compile.framebuffer_fetch_enable"}
!18 = !{!"Apple metal version 32023.883 (metalfe-32023.883)"}
!19 = !{i32 2, i32 8, i32 0}
!20 = !{!"Metal", i32 3, i32 0, i32 0}
!21 = !{!"/private/tmp/tex.metal"}
!22 = !{!23}
!23 = distinct !{!23, !24, !"air-alias-scope-textures"}
!24 = distinct !{!24, !"air-alias-scopes(invert)"}
