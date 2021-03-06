--[[
 * Copyright (C) 2016 Red Hat, Inc.
 * Author: Bastien Nocera <hadess@hadess.net>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA.
 *
--]]

require "lib.utils"
local archive = require "archive"

-- From: https://packages.ubuntu.com/precise/libcaca0
LIBCACA_URLS_PRECISE = {
	["i386"] = 'https://packages.ubuntu.com/precise/i386/libcaca0/download',
	['x86_64'] = 'https://packages.ubuntu.com/precise/amd64/libcaca0/download'
}

-- From: https://packages.ubuntu.com/trusty/libcaca0
LIBCACA_URLS_TRUSTY = {
	["i386"] = 'https://packages.ubuntu.com/trusty/i386/libcaca0/download',
	['x86_64'] = 'https://packages.ubuntu.com/trusty/amd64/libcaca0/download'
}

LIBCACA_URLS = {
	["1.2"] = LIBCACA_URLS_PRECISE,
	["1.4"] = LIBCACA_URLS_TRUSTY
}

-- From: https://packages.ubuntu.com/precise/libslang2
LIBSLANG_URLS_PRECISE = {
	["i386"] = 'https://packages.ubuntu.com/precise/i386/libslang2/download',
	['x86_64'] = 'https://packages.ubuntu.com/precise/amd64/libslang2/download'
}

-- From: https://packages.ubuntu.com/trusty/libslang2
LIBSLANG_URLS_TRUSTY = {
	["i386"] = 'https://packages.ubuntu.com/trusty/i386/libslang2/download',
	['x86_64'] = 'https://packages.ubuntu.com/trusty/amd64/libslang2/download'
}

LIBSLANG_URLS = {
	["1.2"] = LIBSLANG_URLS_PRECISE,
	["1.4"] = LIBSLANG_URLS_TRUSTY
}

-- From: https://packages.ubuntu.com/precise/libjack0
LIBJACK_URLS_PRECISE = {
	["i386"] = 'https://packages.ubuntu.com/precise/i386/libjack0/download',
	['x86_64'] = 'https://packages.ubuntu.com/precise/amd64/libjack0/download'
}

-- From: https://packages.ubuntu.com/trusty/libjack0
LIBJACK_URLS_TRUSTY = {
	["i386"] = 'https://packages.ubuntu.com/trusty/i386/libjack0/download',
	['x86_64'] = 'https://packages.ubuntu.com/trusty/amd64/libjack0/download'
}

LIBJACK_URLS = {
	["1.2"] = LIBJACK_URLS_PRECISE,
	["1.4"] = LIBJACK_URLS_TRUSTY
}

function verify_missing_lib_args(root_dir, framework_version, arch)
	if not root_dir then
		return false, ('Missing root directory')
	end
	if framework_version ~= '1.4' and
	   framework_version ~= '1.2' then
		return false, ('Unsupported framework version ' .. (framework_version or '<unset>'))
	end
	if arch ~= 'i386' and
	   arch ~= 'x86_64' then
		return false, ('Unsupported architecture ' .. (arch or '<unset>'))
	end

	return true
end

function get_libcaca_dl_page_url(framework_version, arch)
	return LIBCACA_URLS[framework_version][arch]
end

function get_libslang_dl_page_url(framework_version, arch)
	return LIBSLANG_URLS[framework_version][arch]
end

function get_libjack_dl_page_url(framework_version, arch)
	return LIBJACK_URLS[framework_version][arch]
end

function parse_deb_download_page(body)
	return body:match('href="(http://mirrors%.kernel%.org.-)">')
end

function read_entry_data(ar)
	local ar_file_content = {}
	while true do
		local data = ar:data()
		if nil == data then break end
		ar_file_content[#ar_file_content + 1] = data
	end
	ar_file_content = table.concat(ar_file_content)

	return ar_file_content
end

function unpack_deb(data, fname_match)
	local read = false
	local function reader(ar)
		if read then
			return nil
		end
		return data
	end

	ar = archive.read { reader = reader }
	local header = ar:next_header()
	while header do
		if header:pathname() == 'data.tar.xz' or
		   header:pathname() == 'data.tar.gz' then
			break
		end
		-- FIXME this is a bit fragile as next_header()
		-- returns an error for "ar" archives when reaching the
		-- end instead of an EOF
		header = ar:next_header()
	end
	if not header then return nil end

	data = read_entry_data(ar)
	-- New data gathered!
	ar:close()
	if not data then return nil end

	ar = archive.read { reader = reader }
	local header = ar:next_header()
	while header do
		path = header:pathname()
		if path:match(fname_match) then
			break
		end
		header = ar:next_header()
	end

	data = read_entry_data(ar)
	ar:close()

	return data
end

function unpack_libcaca_deb(data)
	return unpack_deb(data, '.-(libcaca%.so%.0%..-)$')
end

function unpack_libslang_deb(data)
	return unpack_deb(data, '.-(libslang%.so%.2%..-)$')
end

function unpack_libjack_deb(data)
	return unpack_deb(data, '.-(libjack%.so%.0%..-)$')
end

function add_missing_libcaca(root_dir, framework_version, arch)
	local ret, error = verify_missing_lib_args(root_dir, framework_version, arch)
	if not ret then
		return false, error
	end

	local url = get_libcaca_dl_page_url(framework_version, arch)
	local body = get_url(url)
	if not body then
		return false, 'Failed to get download page at ' .. url
	end
	local pkg_url = parse_deb_download_page(body)
	local pkg = get_url(pkg_url)
	local lib_data = unpack_libcaca_deb(pkg)

	local target_lib_dir = find_lib_dir(root_dir, arch)
	if not target_lib_dir then
		target_lib_dir = root_dir .. '/files/lib/'
	end
	local target_lib_path = target_lib_dir .. '/libcaca.so.0'
	local fd = io.output(target_lib_path)
	fd:write(lib_data)
	fd:close()

	return true
end

function add_missing_libslang(root_dir, framework_version, arch)
	local ret, error = verify_missing_lib_args(root_dir, framework_version, arch)
	if not ret then
		return false, error
	end

	local url = get_libslang_dl_page_url(framework_version, arch)
	local body = get_url(url)
	if not body then
		return false, 'Failed to get download page at ' .. url
	end
	local pkg_url = parse_deb_download_page(body)
	local pkg = get_url(pkg_url)
	local lib_data = unpack_libslang_deb(pkg)

	local target_lib_dir = find_lib_dir(root_dir, arch)
	if not target_lib_dir then
		target_lib_dir = root_dir .. '/files/lib/'
	end
	local target_lib_path = target_lib_dir .. '/libslang.so.2'
	local fd = io.output(target_lib_path)
	fd:write(lib_data)
	fd:close()

	return true
end

function add_missing_libjack(root_dir, framework_version, arch)
	local ret, error = verify_missing_lib_args(root_dir, framework_version, arch)
	if not ret then
		return false, error
	end

	local url = get_libjack_dl_page_url(framework_version, arch)
	local body = get_url(url)
	if not body then
		return false, 'Failed to get download page at ' .. url
	end
	local pkg_url = parse_deb_download_page(body)
	local pkg = get_url(pkg_url)
	local lib_data = unpack_libjack_deb(pkg)

	local target_lib_dir = find_lib_dir(root_dir, arch)
	if not target_lib_dir then
		target_lib_dir = root_dir .. '/files/lib/'
	end
	local target_lib_path = target_lib_dir .. '/libjack.so.0'
	local fd = io.output(target_lib_path)
	fd:write(lib_data)
	fd:close()

	return true
end
