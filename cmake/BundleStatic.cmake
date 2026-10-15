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
    # ar has no merge flag; its MRI script language does the job, and the
    # script arrives on stdin, which is why this one goes through a shell.
    #
    # Both archives are staged under fixed names first. ar splits its script
    # on whitespace and offers no quoting, so a build directory with a space
    # in it would otherwise break the merge -- and fixed names keep the script
    # itself free of generator expressions, which a multi-config generator
    # would otherwise want to write to one filename with differing contents.
    set(staging "${CMAKE_CURRENT_BINARY_DIR}/bundle-${target}/$<CONFIG>")
    set(script "${CMAKE_CURRENT_BINARY_DIR}/bundle-${target}.mri")
    file(WRITE "${script}"
"create bundled.a
addlib target.a
addlib dependency.a
save
end
")

    # Two blocks: WORKING_DIRECTORY applies to every command in the one it is
    # given, and the staging directory has to exist before anything can run
    # inside it.
    add_custom_command(TARGET ${target} POST_BUILD
      COMMAND "${CMAKE_COMMAND}" -E make_directory "${staging}"
      COMMAND "${CMAKE_COMMAND}" -E copy "$<TARGET_FILE:${target}>" "${staging}/target.a"
      COMMAND "${CMAKE_COMMAND}" -E copy "$<TARGET_FILE:${dependency}>" "${staging}/dependency.a"
      COMMENT "Bundling ${dependency} into ${target}"
      VERBATIM)
    add_custom_command(TARGET ${target} POST_BUILD
      COMMAND sh -c "'${CMAKE_AR}' -M < '${script}'"
      COMMAND "${CMAKE_COMMAND}" -E copy "${staging}/bundled.a" "$<TARGET_FILE:${target}>"
      WORKING_DIRECTORY "${staging}"
      VERBATIM)
  endif()

  # The link line no longer says this, now that the objects live inside.
  add_dependencies(${target} ${dependency})
endfunction()
