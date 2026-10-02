#define _WIN32_WINNT 0x0600
#include <windows.h>
#include <cmath>
#include <vector>
#include <cstdint>
#include <cstdio>
#include <cstdlib>

// ==================== НАСТРОЙКИ ====================
const int WIDTH  = 960;
const int HEIGHT = 600;
const float GRAVITY   = 0.6f;
const float JUMP_VEL  = -11.0f;
const float MOVE_ACC  = 0.9f;
const float MAX_SPEED = 6.0f;
const float FRICTION  = 0.82f;
const int   TILE      = 32;

// ==================== ЦВЕТА ====================
inline uint32_t Color(int r, int g, int b) {
    if (r < 0) r = 0; if (r > 255) r = 255;
    if (g < 0) g = 0; if (g > 255) g = 255;
    if (b < 0) b = 0; if (b > 255) b = 255;
    return ((uint32_t)r << 16) | ((uint32_t)g << 8) | ((uint32_t)b);
}

// ==================== БУФЕР ====================
uint32_t* g_fb = nullptr;

inline void SetPixel(int x, int y, uint32_t c) {
    if (x < 0 || x >= WIDTH || y < 0 || y >= HEIGHT) return;
    g_fb[y * WIDTH + x] = c;
}

void FillRect(int x, int y, int w, int h, uint32_t c) {
    int x0 = x < 0 ? 0 : x, x1 = x + w > WIDTH ? WIDTH : x + w;
    int y0 = y < 0 ? 0 : y, y1 = y + h > HEIGHT ? HEIGHT : y + h;
    for (int yy = y0; yy < y1; ++yy) {
        uint32_t* row = g_fb + yy * WIDTH;
        for (int xx = x0; xx < x1; ++xx) row[xx] = c;
    }
}

void FillCircle(int cx, int cy, int r, uint32_t c) {
    int r2 = r * r;
    for (int dy = -r; dy <= r; ++dy)
        for (int dx = -r; dx <= r; ++dx)
            if (dx*dx + dy*dy <= r2)
                SetPixel(cx + dx, cy + dy, c);
}

// ==================== ВВОД ====================
bool KeyDown(int vk) {
    return (GetAsyncKeyState(vk) & 0x8000) != 0;
}

// ==================== УРОВЕНЬ ====================
// Символы: '#' стена, '.' пусто, 'S' старт, 'C' монета, 'E' враг,
//          '^' шипы, 'F' финиш
const char* LEVEL_1[] = {
    "................................................................",
    "................................................................",
    "..........................CCCC................................",
    ".........................######...............................",
    ".................................................CCCC.........",
    "................................................######........",
    "...............................C..............................",
    ".............................#####............................",
    "..............................................E...............",
    "...................C.................................C........",
    ".................#####.............................#####......",
    "......S.......................^^..............F...............",
    "############################^^#################################",
    "############################^^#################################",
};

const int LEVEL_W = 64;
const int LEVEL_H = 14;

int Map[LEVEL_H][LEVEL_W];

void LoadLevel(const char** src, float& sx, float& sy, int& coinsTotal) {
    coinsTotal = 0;
    for (int y = 0; y < LEVEL_H; ++y)
        for (int x = 0; x < LEVEL_W; ++x) {
            char c = (x < (int)strlen(src[y])) ? src[y][x] : '.';
            int val = 0;
            if (c == '#') val = 1;
            else if (c == 'S') { sx = (float)(x * TILE); sy = (float)(y * TILE); }
            else if (c == 'C') { val = 2; coinsTotal++; }
            else if (c == 'E') val = 3;
            else if (c == '^') val = 4;
            else if (c == 'F') val = 5;
            Map[y][x] = val;
        }
}

// ==================== СУЩНОСТИ ====================
struct Player {
    float x, y;
    float vx, vy;
    bool onGround;
    int lives;
    int coins;
    int facing; // 1 = вправо, -1 = влево
    int animFrame;
} p;

struct Enemy {
    float x, y;
    float vx;
    bool alive;
    int dir;
};

std::vector<Enemy> enemies;
int g_coinsTotal = 0;
int g_coinsLeft = 0;
int g_levelWon = 0;
int g_score = 0;
float g_camera = 0;

// ==================== УТИЛИТЫ КАРТЫ ====================
inline int GetTile(int tx, int ty) {
    if (tx < 0 || tx >= LEVEL_W || ty < 0 || ty >= LEVEL_H) return 0;
    return Map[ty][tx];
}

bool AABBCollide(float x, float y, int w, int h) {
    int x0 = (int)((x) / TILE);
    int y0 = (int)((y) / TILE);
    int x1 = (int)((x + w - 1) / TILE);
    int y1 = (int)((y + h - 1) / TILE);
    for (int ty = y0; ty <= y1; ++ty)
        for (int tx = x0; tx <= x1; ++tx) {
            int t = GetTile(tx, ty);
            if (t == 1) return true;
        }
    return false;
}

// ==================== ИГРОК ====================
const int PW = 24;
const int PH = 32;

void ResetPlayer(float sx, float sy) {
    p.x = sx; p.y = sy;
    p.vx = 0; p.vy = 0;
    p.onGround = false;
    p.facing = 1;
    p.animFrame = 0;
}

void UpdatePlayer() {
    if (g_levelWon) return;

    // Ввод
    float ax = 0;
    if (KeyDown('A') || KeyDown(VK_LEFT))  ax -= MOVE_ACC;
    if (KeyDown('D') || KeyDown(VK_RIGHT)) ax += MOVE_ACC;

    if (ax < 0) p.facing = -1;
    if (ax > 0) p.facing = 1;

    p.vx += ax;
    if (fabsf(p.vx) < 0.1f) p.vx = 0;
    if (p.vx >  MAX_SPEED) p.vx =  MAX_SPEED;
    if (p.vx < -MAX_SPEED) p.vx = -MAX_SPEED;

    // Прыжок
    if ((KeyDown('W') || KeyDown(VK_UP) || KeyDown(VK_SPACE)) && p.onGround) {
        p.vy = JUMP_VEL;
        p.onGround = false;
    }

    // Гравитация
    p.vy += GRAVITY;
    if (p.vy > 16) p.vy = 16;

    // Движение по X
    float nx = p.x + p.vx;
    if (!AABBCollide(nx, p.y, PW, PH)) {
        p.x = nx;
    } else {
        // Пробуем сдвинуть на чуть-чуть (шаг)
        if (p.vx > 0) {
            int tx = (int)((p.x + PW) / TILE);
            p.x = tx * TILE - PW;
        } else {
            int tx = (int)(p.x / TILE);
            p.x = (tx + 1) * TILE;
        }
        p.vx = 0;
    }

    // Движение по Y
    float ny = p.y + p.vy;
    if (!AABBCollide(p.x, ny, PW, PH)) {
        p.y = ny;
        p.onGround = false;
    } else {
        if (p.vy > 0) {
            int ty = (int)((p.y + PH) / TILE);
            p.y = ty * TILE - PH;
            p.onGround = true;
        } else {
            int ty = (int)(p.y / TILE);
            p.y = (ty + 1) * TILE;
        }
        p.vy = 0;
    }

    // Анимация
    if (fabsf(p.vx) > 0.5f) p.animFrame++;

    // Падение вниз
    if (p.y > LEVEL_H * TILE + 100) {
        p.lives--;
        if (p.lives <= 0) {
            // Рестарт
            p.lives = 3;
            p.coins = 0;
        }
        // На старт
        p.x = 6 * TILE;
        p.y = 10 * TILE;
        p.vx = p.vy = 0;
    }

    // Столкновения с тайлами (монеты, шипы, финиш)
    int x0 = (int)(p.x / TILE);
    int y0 = (int)(p.y / TILE);
    int x1 = (int)((p.x + PW - 1) / TILE);
    int y1 = (int)((p.y + PH - 1) / TILE);
    for (int ty = y0; ty <= y1; ++ty) {
        for (int tx = x0; tx <= x1; ++tx) {
            if (tx < 0 || tx >= LEVEL_W || ty < 0 || ty >= LEVEL_H) continue;
            int t = Map[ty][tx];
            if (t == 2) {
                // Монета
                Map[ty][tx] = 0;
                p.coins++;
                g_score += 100;
                g_coinsLeft--;
            } else if (t == 4) {
                // Шипы — минус жизнь
                p.lives--;
                if (p.lives <= 0) p.lives = 3;
                p.x = 6 * TILE; p.y = 10 * TILE;
                p.vx = p.vy = 0;
                return;
            } else if (t == 5) {
                // Финиш
                g_levelWon = 1;
                g_score += 1000;
            }
        }
    }
}

// ==================== ВРАГИ ====================
void UpdateEnemies() {
    for (auto& e : enemies) {
        if (!e.alive) continue;
        e.x += e.vx;
        // Проверка стены
        if (AABBCollide(e.x, e.y, 24, 24)) {
            e.x -= e.vx;
            e.vx = -e.vx;
        }
        // Падение в пропасть
        if (e.y > LEVEL_H * TILE + 200) e.alive = false;
    }
}

void PlayerEnemyCollision() {
    for (auto& e : enemies) {
        if (!e.alive) continue;
        if (p.x + PW > e.x && p.x < e.x + 24 &&
            p.y + PH > e.y && p.y < e.y + 24) {
            // Прыжок сверху?
            if (p.vy > 0 && p.y + PH - p.vy <= e.y + 8) {
                e.alive = false;
                p.vy = JUMP_VEL * 0.7f;
                g_score += 200;
            } else {
                // Урон
                p.lives--;
                if (p.lives <= 0) p.lives = 3;
                p.x = 6 * TILE; p.y = 10 * TILE;
                p.vx = p.vy = 0;
                return;
            }
        }
    }
}

// ==================== ОТРИСОВКА ====================
void DrawBackground() {
    // Градиент неба
    for (int y = 0; y < HEIGHT; ++y) {
        int r = 60 + y / 10;
        int g = 120 + y / 8;
        int b = 200 - y / 4;
        uint32_t c = Color(r, g, b);
        uint32_t* row = g_fb + y * WIDTH;
        for (int x = 0; x < WIDTH; ++x) row[x] = c;
    }

    // Параллакс-холмы
    int cam = (int)g_camera;
    for (int layer = 0; layer < 3; ++layer) {
        int speed = 1 + layer * 2;
        int baseY = HEIGHT - 100 - layer * 40;
        int r = 80 + layer * 20;
        int g = 100 + layer * 30;
        int b = 140 + layer * 20;
        uint32_t col = Color(r, g, b);
        for (int x = 0; x < WIDTH; ++x) {
            int wx = x + cam / speed;
            int h = (int)(sinf(wx * 0.008f) * 40 + 60);
            for (int y = baseY - h; y < baseY; ++y)
                SetPixel(x, y, col);
        }
    }

    // Облака
    for (int i = 0; i < 8; ++i) {
        int cx = ((i * 300 - cam / 4) % (WIDTH + 400)) - 200;
        int cy = 50 + (i * 37) % 100;
        FillCircle(cx, cy, 25, Color(255, 255, 255));
        FillCircle(cx + 20, cy + 5, 20, Color(255, 255, 255));
        FillCircle(cx - 20, cy + 5, 20, Color(255, 255, 255));
    }
}

void DrawTile(int tx, int ty, int camX) {
    int t = GetTile(tx, ty);
    if (t == 0) return;
    int sx = tx * TILE - camX;
    int sy = ty * TILE;

    if (t == 1) {
        // Земля с текстурой
        FillRect(sx, sy, TILE, TILE, Color(110, 70, 40));
        FillRect(sx, sy, TILE, 6, Color(60, 150, 60));   // трава сверху
        // Крапинки
        for (int i = 0; i < 8; ++i) {
            int px = sx + (i * 7 + tx * 13) % TILE;
            int py = sy + 10 + (i * 11 + ty * 17) % (TILE - 12);
            SetPixel(px, py, Color(80, 50, 25));
        }
    } else if (t == 2) {
        // Монета
        int cx = sx + TILE / 2, cy = sy + TILE / 2;
        FillCircle(cx, cy, 10, Color(255, 215, 0));
        FillCircle(cx, cy, 6, Color(255, 240, 100));
    } else if (t == 4) {
        // Шипы
        for (int i = 0; i < 4; ++i) {
            int bx = sx + i * 8;
            for (int y = 0; y < 12; ++y) {
                int w = 12 - y;
                FillRect(bx + (8 - w) / 2, sy + TILE - 12 + y, w, 1,
                         Color(200, 50, 50));
            }
        }
    } else if (t == 5) {
        // Финиш — флаг
        FillRect(sx + 14, sy - TILE * 2, 4, TILE * 3, Color(150, 150, 150));
        FillRect(sx + 18, sy - TILE * 2, 20, 14, Color(255, 50, 50));
        FillRect(sx + 18, sy - TILE * 2 + 14, 20, 14, Color(255, 255, 255));
    } else if (t == 3) {
        // Враг на карте (спавн)
    }
}

void DrawPlayer(int camX) {
    int sx = (int)p.x - camX;
    int sy = (int)p.y;

    // Тело
    FillRect(sx + 2, sy + 8, PW - 4, PH - 8, Color(60, 120, 220));
    // Голова
    FillCircle(sx + PW/2, sy + 10, 11, Color(255, 220, 180));
    // Глаза
    int eyeOff = p.facing > 0 ? 3 : -3;
    FillCircle(sx + PW/2 + eyeOff, sy + 8, 2, Color(0, 0, 0));
    FillCircle(sx + PW/2 + eyeOff - 5, sy + 8, 2, Color(0, 0, 0));
    // Ноги (анимация)
    int legPhase = (p.animFrame / 6) % 2;
    int lx = legPhase ? -3 : 3;
    FillRect(sx + 3, sy + PH - 6, 8, 6, Color(40, 40, 80));
    FillRect(sx + PW - 11, sy + PH - 6, 8, 6, Color(40, 40, 80));
    (void)lx;
}

void DrawEnemies(int camX) {
    for (auto& e : enemies) {
        if (!e.alive) continue;
        int sx = (int)e.x - camX;
        int sy = (int)e.y;

        // Тело
        FillRect(sx, sy + 4, 24, 20, Color(200, 60, 60));
        // Глаза
        FillCircle(sx + 7, sy + 12, 3, Color(255, 255, 255));
        FillCircle(sx + 17, sy + 12, 3, Color(255, 255, 255));
        FillCircle(sx + 7, sy + 12, 1, Color(0, 0, 0));
        FillCircle(sx + 17, sy + 12, 1, Color(0, 0, 0));
        // Рот
        FillRect(sx + 6, sy + 18, 12, 2, Color(0, 0, 0));
    }
}

// Простой шрифт 5x7
void DrawChar(int x, int y, char c, uint32_t col);
void DrawText(int x, int y, const char* s, uint32_t col) {
    while (*s) {
        DrawChar(x, y, *s, col);
        x += 8;
        s++;
    }
}

// 5x7 шрифт для базовых символов
const unsigned char FONT[][5] = {
    {0x00,0x00,0x00,0x00,0x00}, // space
    {0x3E,0x51,0x49,0x45,0x3E}, // 0
    {0x00,0x42,0x7F,0x40,0x00}, // 1
    {0x42,0x61,0x51,0x49,0x46}, // 2
    {0x21,0x41,0x45,0x4B,0x31}, // 3
    {0x18,0x14,0x12,0x7F,0x10}, // 4
    {0x27,0x45,0x45,0x45,0x39}, // 5
    {0x3C,0x4A,0x49,0x49,0x30}, // 6
    {0x01,0x71,0x09,0x05,0x03}, // 7
    {0x36,0x49,0x49,0x49,0x36}, // 8
    {0x06,0x49,0x49,0x29,0x1E}, // 9
    // 10..35 = A..Z
    {0x7E,0x11,0x11,0x11,0x7E}, // A
    {0x7F,0x49,0x49,0x49,0x36}, // B
    {0x3E,0x41,0x41,0x41,0x22}, // C
    {0x7F,0x41,0x41,0x22,0x1C}, // D
    {0x7F,0x49,0x49,0x49,0x41}, // E
    {0x7F,0x09,0x09,0x09,0x01}, // F
    {0x3E,0x41,0x49,0x49,0x7A}, // G
    {0x7F,0x08,0x08,0x08,0x7F}, // H
    {0x00,0x41,0x7F,0x41,0x00}, // I
    {0x20,0x40,0x41,0x3F,0x01}, // J
    {0x7F,0x08,0x14,0x22,0x41}, // K
    {0x7F,0x40,0x40,0x40,0x40}, // L
    {0x7F,0x02,0x0C,0x02,0x7F}, // M
    {0x7F,0x04,0x08,0x10,0x7F}, // N
    {0x3E,0x41,0x41,0x41,0x3E}, // O
    {0x7F,0x09,0x09,0x09,0x06}, // P
    {0x3E,0x41,0x51,0x21,0x5E}, // Q
    {0x7F,0x09,0x19,0x29,0x46}, // R
    {0x46,0x49,0x49,0x49,0x31}, // S
    {0x01,0x01,0x7F,0x01,0x01}, // T
    {0x3F,0x40,0x40,0x40,0x3F}, // U
    {0x1F,0x20,0x40,0x20,0x1F}, // V
    {0x3F,0x40,0x38,0x40,0x3F}, // W
    {0x63,0x14,0x08,0x14,0x63}, // X
    {0x07,0x08,0x70,0x08,0x07}, // Y
    {0x61,0x51,0x49,0x45,0x43}, // Z
    {0x00,0x00,0x00,0x00,0x00}, // [
    {0x00,0x00,0x00,0x00,0x00}, // backslash
    {0x00,0x00,0x00,0x00,0x00}, // ]
    {0x00,0x00,0x00,0x00,0x00}, // ^
    {0x00,0x00,0x00,0x00,0x00}, // _
};

void DrawChar(int x, int y, char c, uint32_t col) {
    int idx = -1;
    if (c == ' ') idx = 0;
    else if (c >= '0' && c <= '9') idx = 1 + (c - '0');
    else if (c >= 'A' && c <= 'Z') idx = 11 + (c - 'A');
    else if (c >= 'a' && c <= 'z') idx = 11 + (c - 'a');
    if (idx < 0 || idx > 36) return;

    for (int i = 0; i < 5; ++i) {
        unsigned char b = FONT[idx][i];
        for (int j = 0; j < 7; ++j) {
            if (b & (1 << j)) {
                SetPixel(x + i, y + j, col);
                SetPixel(x + i, y + j, col);
            }
        }
    }
}

void DrawHUD() {
    char buf[128];
    sprintf_s(buf, "SCORE: %d", g_score);
    DrawText(20, 20, buf, Color(255, 255, 255));

    sprintf_s(buf, "LIVES: %d", p.lives);
    DrawText(20, 40, buf, Color(255, 100, 100));

    sprintf_s(buf, "COINS: %d", p.coins);
    DrawText(20, 60, buf, Color(255, 215, 0));

    if (g_levelWon) {
        const char* msg = "LEVEL COMPLETE!";
        int len = (int)strlen(msg);
        int tw = len * 8;
        FillRect(WIDTH/2 - tw/2 - 20, HEIGHT/2 - 30, tw + 40, 60,
                 Color(0, 0, 0));
        DrawText(WIDTH/2 - tw/2, HEIGHT/2 - 8, msg, Color(0, 255, 0));
    }
}

// ==================== ЛОГИКА УРОВНЯ ====================
void SetupLevel() {
    float sx = 3 * TILE, sy = 10 * TILE;
    LoadLevel(LEVEL_1, sx, sy, g_coinsTotal);
    g_coinsLeft = g_coinsTotal;
    ResetPlayer(sx, sy);

    // Спавн врагов
    enemies.clear();
    for (int y = 0; y < LEVEL_H; ++y)
        for (int x = 0; x < LEVEL_W; ++x)
            if (Map[y][x] == 3) {
                Enemy e;
                e.x = (float)(x * TILE);
                e.y = (float)(y * TILE);
                e.vx = ((x % 2) ? 1.5f : -1.5f);
                e.alive = true;
                e.dir = 1;
                enemies.push_back(e);
                Map[y][x] = 0; // убираем маркер спавна
            }

    g_levelWon = 0;
    g_score = 0;
    p.coins = 0;
    p.lives = 3;
}

// ==================== ОКНО ====================
LRESULT CALLBACK WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_CREATE:
        SetTimer(hWnd, 1, 16, NULL);
        return 0;
    case WM_TIMER:
        if (!g_levelWon) {
            UpdatePlayer();
            UpdateEnemies();
            PlayerEnemyCollision();
        }
        // Камера за игроком
        g_camera = p.x - WIDTH / 2 + PW / 2;
        if (g_camera < 0) g_camera = 0;
        if (g_camera > LEVEL_W * TILE - WIDTH)
            g_camera = (float)(LEVEL_W * TILE - WIDTH);

        InvalidateRect(hWnd, NULL, FALSE);
        return 0;
    case WM_KEYDOWN:
        if (wParam == VK_ESCAPE) PostQuitMessage(0);
        if (wParam == 'R') SetupLevel();
        return 0;
    case WM_PAINT: {
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(hWnd, &ps);

        // Рисуем всё в буфер
        DrawBackground();

        int camX = (int)g_camera;
        for (int ty = 0; ty < LEVEL_H; ++ty)
            for (int tx = 0; tx < LEVEL_W; ++tx)
                DrawTile(tx, ty, camX);

        DrawEnemies(camX);
        DrawPlayer(camX);
        DrawHUD();

        // На экран
        BITMAPINFO bi = {0};
        bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        bi.bmiHeader.biWidth = WIDTH;
        bi.bmiHeader.biHeight = -HEIGHT;
        bi.bmiHeader.biPlanes = 1;
        bi.bmiHeader.biBitCount = 32;
        bi.bmiHeader.biCompression = BI_RGB;
        SetDIBitsToDevice(hdc, 0, 0, WIDTH, HEIGHT, 0, 0, 0, HEIGHT,
                          g_fb, &bi, DIB_RGB_COLORS);

        EndPaint(hWnd, &ps);
        return 0;
    }
    case WM_DESTROY:
        KillTimer(hWnd, 1);
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(hWnd, msg, wParam, lParam);
}

// ==================== MAIN ====================
int WINAPI wWinMain(HINSTANCE hInst, HINSTANCE, LPWSTR, int) {
    g_fb = new uint32_t[WIDTH * HEIGHT];
    SetupLevel();

    WNDCLASSW wc = {0};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInst;
    wc.lpszClassName = L"PlatformerWnd";
    wc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    RegisterClassW(&wc);

    DWORD style = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX;
    RECT rc = {0, 0, WIDTH, HEIGHT};
    AdjustWindowRect(&rc, style, FALSE);

    HWND hWnd = CreateWindowExW(0, L"PlatformerWnd",
        L"Platformer — A/D ходить, W прыгать, R рестарт, ESC выход",
        style, CW_USEDEFAULT, CW_USEDEFAULT,
        rc.right - rc.left, rc.bottom - rc.top,
        NULL, NULL, hInst, NULL);

    ShowWindow(hWnd, SW_SHOW);
    UpdateWindow(hWnd);
    SetForegroundWindow(hWnd);
    SetFocus(hWnd);

    MSG msg;
    while (GetMessageW(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    delete[] g_fb;
    return 0;
}
