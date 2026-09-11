#[cfg(test)]
mod tests {
    use glib::prelude::*;

    // RUSTSEC-2024-0429 is visible under optimization: an immutable FFI out
    // pointer can remain null. Exercise all five affected iterator methods.
    #[test]
    fn variant_string_iterator_ffi_out_pointer_is_initialized() {
        let strings = ["first", "北邮", "", "last"];
        let variant = strings.to_variant();
        let mut iter = variant.array_iter_str().unwrap();
        assert_eq!(iter.next(), Some("first"));
        assert_eq!(iter.next_back(), Some("last"));
        assert_eq!(iter.next(), Some("北邮"));
        assert_eq!(iter.next_back(), Some(""));
        assert_eq!(iter.next(), None);
        assert_eq!(variant.array_iter_str().unwrap().nth(1), Some("北邮"));
        assert_eq!(variant.array_iter_str().unwrap().nth_back(1), Some(""));
        assert_eq!(variant.array_iter_str().unwrap().last(), Some("last"));
        assert_eq!(
            variant.array_iter_str().unwrap().collect::<Vec<_>>(),
            strings
        );
    }
}
