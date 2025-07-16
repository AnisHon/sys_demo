extern "C" {
    extern void _printk(const char *msg);
}


void _printk(const char *msg) {
    return;
}

int main() {
    while (true) {}
}