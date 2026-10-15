# Folding a dependency's objects into one of our archives.
#
# A static library does not contain what it links. Without this, installing
# weaklink also means installing PortAudio's archive beside it, and a
# consumer's prefix ends up carrying a libportaudio.a that is ours rather than
# theirs. Merging the objects in means the installed tree holds weaklink's
# libraries and nothing else.

# Reports whether archives can be merged on this toolchain.
function(weaklink_can_bundle_archives out_var)
  if(APPLE)
    set(${out_var} ON PARENT_SCOPE)
  elseif(UNIX AND NOT MSVC AND CMAKE_AR)
    set(${out_var} ON PARENT_SCOPE)
  else()
    set(${out_var} OFF PARENT_SCOPE)
  endif()
endfunction()

# Merges <dependency>'s archive into <target>'s, after <target> is built.
function(weaklink_bundle_archive target dependency)
  if(APPLE)
    add_custom_command(TARGET ${target} POST_BUILD
      COMMAND libtool -static -o "$<TARGET_FILE:${target}>.bundled"
              "$<TARGET_FILE:${target}>" "$<TARGET_FILE:${dependency}>"
      COMMAND "${CMAKE_COMMAND}" -E rename
              "$<TARGET_FILE:${target}>.bundled" "$<TARGET_FILE:${target}>"
      COMMENT "Bundling ${dependency} into ${target}"
      VERBATIM)
  else()
    # ar has no merge flag; its MRI script language does the job. The script is
    # generated at build time because it names both archives by path, and it
    # arrives on stdin, which is why this one goes through a shell.
    set(script "${CMAKE_CURRENT_BINARY_DIR}/bundle-${target}.mri")
    file(GENERATE OUTPUT "${script}" CONTENT
"create $<TARGET_FILE:${target}>.bundled
addlib $<TARGET_FILE:${target}>
addlib $<TARGET_FILE:${dependency}>
save
end
")
    add_custom_command(TARGET ${target} POST_BUILD
      COMMAND sh -c "'${CMAKE_AR}' -M < '${script}'"
      COMMAND "${CMAKE_COMMAND}" -E rename
              "$<TARGET_FILE:${target}>.bundled" "$<TARGET_FILE:${target}>"
      COMMENT "Bundling ${dependency} into ${target}"
      VERBATIM)
  endif()

  # The link line no longer says this, now that the objects live inside.
  add_dependencies(${target} ${dependency})
endfunction()
