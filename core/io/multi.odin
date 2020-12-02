package io

import "core:runtime"

@(private)
Multi_Reader :: struct {
	using stream: Stream,
	readers: [dynamic]Reader,
}

@(private)
_multi_reader_vtable := &Stream_VTable{
	impl_read = proc(s: Stream, p: []byte) -> (n: int, err: Error) {
		mr := (^Multi_Reader)(s.stream_data);
		for len(mr.readers) > 0 {
			r := mr.readers[0];
			n, err = read(r, p);
			if err == .EOF {
				ordered_remove(&mr.readers, 0);
			}
			if n > 0 || err != .EOF {
				if err == .EOF && len(mr.readers) > 0 {
					// Don't return EOF yet, more readers remain
					err = nil;
				}
				return;
			}
		}
		return 0, .EOF;
	},
	impl_destroy = proc(s: Stream) -> Error {
		mr := (^Multi_Reader)(s.stream_data);
		context.allocator = mr.readers.allocator;
		delete(mr.readers);
		free(mr);
		return .None;
	},
};

mutlti_reader :: proc(readers: ..Reader, allocator := context.allocator) -> Reader {
	context.allocator = allocator;
	mr := new(Multi_Reader);
	mr.stream_vtable = _multi_reader_vtable;
	mr.stream_data = mr;
	all_readers := make([dynamic]Reader, 0, len(readers));

	for w in readers {
		if w.stream_vtable == _multi_reader_vtable {
			other := (^Multi_Reader)(w.stream_data);
			append(&all_readers, ..other.readers[:]);
		} else {
			append(&all_readers, w);
		}
	}

	mr.readers = all_readers;
	res, _ := to_reader(mr^);
	return res;
}


@(private)
Multi_Writer :: struct {
	using stream: Stream,
	writers:      []Writer,
	allocator:    runtime.Allocator,
}

@(private)
_multi_writer_vtable := &Stream_VTable{
	impl_write = proc(s: Stream, p: []byte) -> (n: int, err: Error) {
		mw := (^Multi_Writer)(s.stream_data);
		for w in mw.writers {
			n, err = write(w, p);
			if err != nil {
				return;
			}
			if n != len(p) {
				err = .Short_Write;
				return;
			}
		}

		return len(p), nil;
	},
	impl_destroy = proc(s: Stream) -> Error {
		mw := (^Multi_Writer)(s.stream_data);
		context.allocator = mw.allocator;
		delete(mw.writers);
		free(mw);
		return .None;
	},
};

mutlti_writer :: proc(writers: ..Writer, allocator := context.allocator) -> Writer {
	context.allocator = allocator;
	mw := new(Multi_Writer);
	mw.stream_vtable = _multi_writer_vtable;
	mw.stream_data = mw;
	mw.allocator = allocator;
	all_writers := make([dynamic]Writer, 0, len(writers));

	for w in writers {
		if w.stream_vtable == _multi_writer_vtable {
			other := (^Multi_Writer)(w.stream_data);
			append(&all_writers, ..other.writers);
		} else {
			append(&all_writers, w);
		}
	}

	mw.writers = all_writers[:];
	res, _ := to_writer(mw^);
	return res;
}
