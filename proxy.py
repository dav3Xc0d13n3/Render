import asyncio
import websockets
import os

async def handler(websocket):
    reader, writer = await asyncio.open_connection('127.0.0.1', 22)
    
    async def ws_to_tcp():
        try:
            async for message in websocket:
                writer.write(message)
                await writer.drain()
        except Exception:
            pass
        finally:
            writer.close()

    async def tcp_to_ws():
        try:
            while True:
                data = await reader.read(4096)
                if not data:
                    break
                await websocket.send(data)
        except Exception:
            pass
        finally:
            await websocket.close()

    await asyncio.gather(ws_to_tcp(), tcp_to_ws())

async def main():
    port = int(os.environ.get("PORT", 8080))
    async with websockets.serve(handler, "0.0.0.0", port):
        print(f"WebSocket SSH bridge listening on {port}")
        await asyncio.Future()

if __name__ == "__main__":
    asyncio.run(main())
