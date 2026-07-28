#target remote localhost:1234
set follow-fork-mode child
set detach-on-fork off
set solib-search-path /home/awcator/ri-project-occulus/dicomweb/third_party/isyntax/src/cmake-build-debug/lib
set breakpoint pending on
break call_DecodeiSyntaxSafe
break call_GetUncompressedDicomHeader
break call_GetPayloadInfo
break call_GetPayloadInfo
sharedlibrary
break DecodeiSyntaxSafe

