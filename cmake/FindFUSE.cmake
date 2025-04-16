
cmake_policy(PUSH)
cmake_minimum_required(VERSION 3.12...3.18 FATAL_ERROR)
if (POLICY CMP0121)
	# Detect invalid indices in list()
	cmake_policy(SET CMP0121 NEW)
endif()
if (POLICY CMP0125)
	# Consistent behavior for cache variables managed by find_*()
	cmake_policy(SET CMP0125 NEW)
endif()
if (POLICY CMP0132)
	# Consistent handling of compiler environment variables
	cmake_policy(SET CMP0132 NEW)
endif()

# docstrings
set(FUSE_INCLUDE_DIRS_DOCSTR "Paths to fuse headers")
set(FUSE_LIBRARIES_DOCSTR "Paths to fuse libraries")
set(FUSE_COMPILE_OPTIONS_DOCSTR "Compile options needed to use fuse")
set(FUSE_LINK_OPTIONS_DOCSTR "Link options needed to use fuse")
set(FUSE_NEEDS_LIBDL_DOCSTR "Whether fuse needs libdl")
set(FUSE_NEEDS_LIBRT_DOCSTR "Whether fuse needs librt")
set(FUSE_NEEDS_PTHREAD_DOCSTR "Whether fuse needs pthread")

# extract fuse version from headers
function(_ffuse_extract_version includedirs)
	foreach(includedir IN LISTS includedirs)
		if (EXISTS "${includedir}/fuse_common.h")
			set(fcommon_header "${includedir}/fuse_common.h")
			break()
		elseif(EXISTS "${includedir}/fuse/fuse_common.h")
			set(fcommon_header "${includedir}/fuse/fuse_common.h")
			break()
		endif()
	endforeach()
	if (NOT fcommon_header)
		message(WARNING "Unable to determine fuse version: could not find fuse_common.h")
		return()
	endif(NOT fcommon_header)

	file(READ "${fcommon_header}" _contents)
	if(_contents MATCHES ".*[\n\r][ \\t]*#[ \\t]*define[ \\t]+FUSE_MAJOR_VERSION[ \\t]+([0-9]+).*")
		set(_FUSE_MAJOR_VERSION "${CMAKE_MATCH_1}")
	endif()
	if(_contents MATCHES ".*[\n\r][ \\t]*#[ \\t]*define[ \\t]+FUSE_MINOR_VERSION[ \\t]+([0-9]+).*")
		set(_FUSE_MINOR_VERSION "${CMAKE_MATCH_1}")
	endif()
	if(_contents MATCHES ".*[\n\r][ \\t]*#[ \\t]*define[ \\t]+FUSE_HOTFIX_VERSION[ \\t]+([0-9]+).*")
		set(_FUSE_HOTFIX_VERSION "${CMAKE_MATCH_1}")
	endif()
	if (_FUSE_MAJOR_VERSION AND (_FUSE_MINOR_VERSION OR (_FUSE_MINOR_VERSION STREQUAL "0")))
		set(FUSE_MAJOR_VERSION "${_FUSE_MAJOR_VERSION}" PARENT_SCOPE)
		set(FUSE_MINOR_VERSION "${_FUSE_MINOR_VERSION}" PARENT_SCOPE)
		if (_FUSE_HOTFIX_VERSION OR (_FUSE_HOTFIX_VERSION STREQUAL "0"))
			set(FUSE_PATCH_VERSION "${_FUSE_HOTFIX_VERSION}" PARENT_SCOPE)
			set(FUSE_VERSION "${_FUSE_MAJOR_VERSION}.${_FUSE_MINOR_VERSION}.${_FUSE_HOTFIX_VERSION}" PARENT_SCOPE)
		else()
			set(FUSE_VERSION "${_FUSE_MAJOR_VERSION}.${_FUSE_MINOR_VERSION}" PARENT_SCOPE)
		endif()
	else()
		message(WARNING "Unable to determine fuse version: could not parse fuse_common.h")
	endif()
endfunction()

# check whether -D_FILE_OFFSET_BITS=64 needs to be added to defines
function(_ffuse_foff_check resultvar_out includedirs cflags)
	get_property(ENABLED_LANGUAGES GLOBAL PROPERTY ENABLED_LANGUAGES)
	if ("CXX" IN_LIST ENABLED_LANGUAGES)
		set(FUSE_TEST_SOURCE "${CMAKE_CURRENT_LIST_DIR}/fuse_test.cpp")
		set(FUSE_TEST_CFLAGS_VAR "CMAKE_CXX_FLAGS")
	elseif ("C" IN_LIST ENABLED_LANGUAGES)
		set(FUSE_TEST_SOURCE "${CMAKE_CURRENT_LIST_DIR}/fuse_test.c")
		set(FUSE_TEST_CFLAGS_VAR "CMAKE_C_FLAGS")
	else()
		message(FATAL_ERROR "Either C or CXX must be enabled.")
	endif()

	if (cflags)
		set(FUSE_TEST_CFLAGS "-D${FUSE_TEST_CFLAGS_VAR}:STRING=${cflags}")
	else()
		set(FUSE_TEST_CFLAGS)
	endif()

	try_compile(
		FUSE_FOFF_CHECK
		"${CMAKE_CURRENT_BINARY_DIR}"
		SOURCES "${FUSE_TEST_SOURCE}"
		CMAKE_FLAGS
		"-DINCLUDE_DIRECTORIES:STRING=${includedirs}"
		"${FUSE_TEST_CFLAGS}"
	)

	if (FUSE_FOFF_CHECK)
		set("${resultvar_out}" FALSE)
	else()
		set("${resultvar_out}" TRUE)
	endif()
endfunction()

# ugliness follows.
# pkg-config is really inadequate for CMake. fuse.pc can pull in librt, libdl, and pthread, all of
# which we have special handling for. Furthermore, there is no clean way to pull the include dirs
# and libraries specific to fuse *and not its dependencies* out of fuse.pc without at least a little
# bit of guesswork/assumption-making. What follows is my clunky attempt at handling this to the
# best of my ability.

# search for a library in pc result variables, remove any entries found, and return paths
function(_ffuse_filter_pc_lib foundvar_out pathsvar_out libname pclibsvar pclibpathsvar)

	set(PC_LIBRARIES "${pclibsvar}")
	set(PC_LINK_LIBRARIES "${${pclibpathsvar}}")
	if ("${${pathsvar_out}}")
		set(LIBPATHS_OUT "${${pathsvar_out}}")
	endif("${${pathsvar_out}}")

	foreach(libprefix IN LISTS CMAKE_FIND_LIBRARY_PREFIXES)
		foreach(libsuffix IN LISTS CMAKE_FIND_LIBRARY_SUFFIXES)
			list(APPEND libfnames "${libprefix}${libname}${libsuffix}")
		endforeach()
	endforeach()

	if ("${libname}" IN_LIST PC_LIBRARIES)
		set("${foundvar_out}" TRUE PARENT_SCOPE)
		list(REMOVE_ITEM PC_LIBRARIES "${libname}")
	endif("${libname}" IN_LIST PC_LIBRARIES)

	foreach(libpath IN LISTS PC_LINK_LIBRARIES)
		cmake_path(GET libpath FILENAME libfname)
		if (libfname IN_LIST libfnames)
			set("${foundvar_out}" TRUE PARENT_SCOPE)
			list(APPEND libpaths "${libpath}")
		endif(libfname IN_LIST libfnames)
	endforeach()

	foreach(libpath IN LISTS libpaths)
		list(APPEND LIBPATHS_OUT "${libpath}")
		list(REMOVE_ITEM PC_LINK_LIBRARIES "${libpath}")
	endforeach()

	set("${pclibsvar}" "${PC_LIBRARIES}" PARENT_SCOPE)
	set("${pclibpathsvar}" "${PC_LINK_LIBRARIES}" PARENT_SCOPE)
	if (LIBPATHS_OUT)
		list(REMOVE_DUPLICATES LIBPATHS_OUT)
		set("${pathsvar_out}" "${LIBPATHS_OUT}" PARENT_SCOPE)
	endif(LIBPATHS_OUT)
endfunction()

# some defaults
set(_FUSE_NEEDS_LIBDL FALSE)
set(_FUSE_NEEDS_LIBRT FALSE)
set(_FUSE_NEEDS_PTHREAD TRUE)

if ((NOT FUSE_INCLUDE_DIRS) AND (NOT FUSE_LIBRARIES))
	find_package(PkgConfig)
	if (PKG_CONFIG_FOUND)
		pkg_check_modules(PC_FUSE "fuse" QUIET)
		if (PC_FUSE_FOUND)

			set(_FUSE_PCLIBS "${PC_FUSE_LIBRARIES}")
			set(_FUSE_PCLIBPATHS "${PC_FUSE_LINK_LIBRARIES}")
			set(_FUSE_LDFLAGS "${PC_FUSE_LDFLAGS_OTHER}")

			# Check for dl
			_ffuse_filter_pc_lib(_FUSE_NEEDS_LIBDL _DL_LIBPATHS "dl" _FUSE_PCLIBS _FUSE_PCLIBPATHS)
			_ffuse_filter_pc_lib(_FUSE_NEEDS_LIBDL _DL_LIBPATHS "${CMAKE_DL_LIBS}" _FUSE_PCLIBS _FUSE_PCLIBPATHS)

			# check for rt
			_ffuse_filter_pc_lib(_FUSE_NEEDS_LIBRT _RT_LIBPATHS "rt" _FUSE_PCLIBS _FUSE_PCLIBPATHS)

			# Check for pthread
			# we default to pulling in pthread, so use a different variable here
			_ffuse_filter_pc_lib(_FUSE_NEEDS_PTHREAD_PC _PTHREAD_LIBPATHS "pthread" _FUSE_PCLIBS _FUSE_PCLIBPATHS)
			if ("-pthread" IN_LIST _FUSE_LDFLAGS)
				set(_FUSE_NEEDS_PTHREAD_PC TRUE)
				list(REMOVE_ITEM _FUSE_LDFLAGS "-pthread")
			endif("-pthread" IN_LIST _FUSE_LDFLAGS)
			if (NOT _FUSE_NEEDS_PTHREAD_PC)
				set(_FUSE_NEEDS_PTHREAD FALSE)
			endif(NOT _FUSE_NEEDS_PTHREAD_PC)

		endif(PC_FUSE_FOUND)
	endif(PKG_CONFIG_FOUND)
endif((NOT FUSE_INCLUDE_DIRS) AND (NOT FUSE_LIBRARIES))

find_path(
	FUSE_INCLUDE_DIRS
	NAMES fuse.h
	PATHS "${PC_FUSE_INCLUDE_DIRS}"
	DOC "${FUSE_INCLUDE_DIRS_DOCSTR}"
)

if (_FUSE_PCLIBPATHS)
	set(FUSE_LIBRARIES "${_FUSE_PCLIBPATHS}" CACHE STRING "${FUSE_LIBRARIES_DOCSTR}")
else()
	find_library(
		FUSE_LIBRARIES
		NAMES "fuse"
		PATHS "${PC_FUSE_LIBRARY_DIRS}"
		DOC "${FUSE_LIBRARIES_DOCSTR}"
	)
endif()

set(FUSE_NEEDS_LIBDL "${_FUSE_NEEDS_LIBDL}" CACHE BOOL "${FUSE_NEEDS_LIBDL_DOCSTR}")
set(FUSE_NEEDS_LIBRT "${_FUSE_NEEDS_LIBRT}" CACHE BOOL "${FUSE_NEEDS_LIBRT_DOCSTR}")
set(FUSE_NEEDS_PTHREAD "${_FUSE_NEEDS_PTHREAD}" CACHE BOOL "${FUSE_NEEDS_PTHREAD_DOCSTR}")

if (FUSE_INCLUDE_DIRS)

	_ffuse_extract_version("${FUSE_INCLUDE_DIRS}")

	if (NOT DEFINED FUSE_COMPILE_OPTIONS)
		if (PC_FUSE_CFLAGS_OTHER)
			set(_FUSE_COMPILE_OPTIONS "${PC_FUSE_CFLAGS_OTHER}")
		endif(PC_FUSE_CFLAGS_OTHER)

		_ffuse_foff_check(_FUSE_NEEDS_FOFF64 "${FUSE_INCLUDE_DIRS}" "${PC_FUSE_CFLAGS_OTHER}")
		if (_FUSE_NEEDS_FOFF64)
			list(APPEND _FUSE_COMPILE_OPTIONS "-D_FILE_OFFSET_BITS=64")
		endif(_FUSE_NEEDS_FOFF64)

		set(FUSE_COMPILE_OPTIONS "${_FUSE_COMPILE_OPTIONS}" CACHE STRING "${FUSE_COMPILE_OPTIONS_DOCSTR}")
	endif(NOT DEFINED FUSE_COMPILE_OPTIONS)

	if (NOT DEFINED FUSE_LINK_OPTIONS)
		set(FUSE_LINK_OPTIONS "${_FUSE_LDFLAGS}" CACHE STRING "${FUSE_LINK_OPTIONS_DOCSTR}")
	endif(NOT DEFINED FUSE_LINK_OPTIONS)

endif(FUSE_INCLUDE_DIRS)

include(FindPackageHandleStandardArgs)

if (FUSE_VERSION)
	find_package_handle_standard_args(
		FUSE
		REQUIRED_VARS FUSE_LIBRARIES FUSE_INCLUDE_DIRS
		VERSION_VAR FUSE_VERSION
	)
else()
	find_package_handle_standard_args(
		FUSE
		REQUIRED_VARS FUSE_LIBRARIES FUSE_INCLUDE_DIRS
	)
endif()

if (FUSE_FOUND AND (NOT TARGET FUSE::FUSE))
	add_library(FUSE::FUSE INTERFACE IMPORTED)

	unset(_ffuse_REQUIRED)
	if (FUSE_FIND_REQUIRED)
		set(_ffuse_REQUIRED REQUIRED)
	endif(FUSE_FIND_REQUIRED)

	# the first library in the list is usually the "main" library
	list(GET FUSE_LIBRARIES 0 _FUSE_TARGET_LIB)
	set_target_properties(
		FUSE::FUSE
		PROPERTIES
		IMPORTED_LOCATION "${_FUSE_TARGET_LIB}"
	)

	set_target_properties(
		FUSE::FUSE
		PROPERTIES
		INTERFACE_LINK_LIBRARIES "${FUSE_LIBRARIES}"
	)

	if (FUSE_NEEDS_LIBDL)
		set_property(
			TARGET FUSE::FUSE
			APPEND
			PROPERTY INTERFACE_LINK_LIBRARIES "${CMAKE_DL_LIBS}"
		)
	endif(FUSE_NEEDS_LIBDL)

	if (FUSE_NEEDS_LIBRT)
		find_package(LibRT ${_ffuse_REQUIRED})
		set_property(
			TARGET FUSE::FUSE
			APPEND
			PROPERTY INTERFACE_LINK_LIBRARIES LibRT::LibRT
		)
	endif(FUSE_NEEDS_LIBRT)

	if (FUSE_NEEDS_PTHREAD)
		find_package(Threads ${_ffuse_REQUIRED})
		set_property(
			TARGET FUSE::FUSE
			APPEND
			PROPERTY INTERFACE_LINK_LIBRARIES Threads::Threads
		)
	endif(FUSE_NEEDS_PTHREAD)

	set_target_properties(
		FUSE::FUSE
		PROPERTIES
		INTERFACE_INCLUDE_DIRECTORIES "${FUSE_INCLUDE_DIRS}"
	)

	if (FUSE_COMPILE_OPTIONS)
		set_target_properties(
			FUSE::FUSE
			PROPERTIES
			INTERFACE_COMPILE_OPTIONS "${FUSE_COMPILE_OPTIONS}"
		)
	endif(FUSE_COMPILE_OPTIONS)

	if (FUSE_LINK_OPTIONS)
		set_target_properties(
			FUSE::FUSE
			PROPERTIES
			INTERFACE_LINK_OPTIONS "${FUSE_LINK_OPTIONS}"
		)
	endif(FUSE_LINK_OPTIONS)

endif(FUSE_FOUND AND (NOT TARGET FUSE::FUSE))

cmake_policy(POP)
