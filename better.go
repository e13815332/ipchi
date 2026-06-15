package better

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
)

// ScanResult 扫描结果
type ScanResult struct {
	IP            string `json:"ip"`
	Bandwidth     int    `json:"bandwidth"`     // 期望带宽 Mbps
	RealBandwidth int    `json:"realBandwidth"` // 实测带宽 Mbps
	MaxSpeed      int    `json:"maxSpeed"`      // 峰值速度 kB/s
	LatencyMs     int    `json:"latencyMs"`
	DataCenter    string `json:"dataCenter"`
	Elapsed       int    `json:"elapsed"` // 总计用时 秒
	Error         string `json:"error"`
}

// SetApiServer 设置 API 服务端地址
func SetApiServer(url string) {
	apiServerURL = url
}

// SetCacheDir 设置缓存目录（Android 应用数据目录）
// gomobile 必须显式设置，Android 下通常设为 Context.getFilesDir()
func SetCacheDir(dir string) {
	dataDir = dir
}

// GetProgress 返回当前进度描述，供 Android 端轮询
func GetProgress() string {
	progressMu.Lock()
	defer progressMu.Unlock()
	return progress
}

func setProgress(s string) {
	progressMu.Lock()
	progress = s
	progressMu.Unlock()
}

// CancelScan 取消正在进行的扫描（立即中断所有网络操作）
func CancelScan() {
	cancelMu.Lock()
	if cancelCancel != nil {
		cancelCancel()
	}
	cancelMu.Unlock()
	setProgress("用户已取消扫描")
}

// ----------------------- 数据中心过滤 -----------------------

var dcFilter string

// SetDataCenterFilter 设置数据中心过滤（空=全部）
func SetDataCenterFilter(dc string) {
	dcFilter = strings.ToUpper(strings.TrimSpace(dc))
}

// GetDataCenters 返回可用的数据中心列表（JSON 数组，含国家备注）
func GetDataCenters() string {
	dcs, err := fetchDCs()
	if err != nil {
		return "[]"
	}
	b, _ := json.Marshal(dcs)
	return string(b)
}

// DCEntry 数据中心条目
type DCEntry struct {
	DC    string `json:"dc"`
	Label string `json:"label"`
}

func isCancelled() bool {
	cancelMu.Lock()
	defer cancelMu.Unlock()
	if cancelCtx == nil {
		return false
	}
	select {
	case <-cancelCtx.Done():
		return true
	default:
		return false
	}
}

func resetCancel() {
	cancelMu.Lock()
	defer cancelMu.Unlock()
	cancelCtx, cancelCancel = context.WithCancel(context.Background())
}

// GetIPs 运行 Cloudflare IP 优选，返回结果 JSON
// v4: true=IPv4 false=IPv6
// useTLS: 是否启用 TLS 握手
// bandwidth: 期望带宽（Mbps），设为 0 则使用默认 1 Mbps
// resultCount: 返回结果数量（1 或 5）
// 阻塞调用，需在后台线程执行
func GetIPs(v4 bool, useTLS bool, bandwidth int, resultCount int) string {
	setProgress("正在初始化...")
	resetCancel()

	ipType := 4
	if !v4 {
		ipType = 6
	}

	if bandwidth <= 0 {
		bandwidth = 1
	}
	if resultCount <= 0 {
		resultCount = 1
	}

	// 转为 kB/s
	speedTarget := bandwidth * 128

	startTime := timeNow()
	results := cloudflareTest(ipType, useTLS, 50, speedTarget, resultCount)
	elapsed := int(timeSince(startTime).Seconds())

	// 填充通用字段
	for i := range results {
		results[i].Bandwidth = bandwidth
		results[i].Elapsed = elapsed
	}

	// 如果第一个结果有 error，包装成兼容格式
	if len(results) == 1 && results[0].Error != "" {
		b, _ := json.Marshal(results[0])
		return string(b)
	}

	type multiResult struct {
		Count   int          `json:"count"`
		Elapsed int          `json:"elapsed"`
		Results []ScanResult `json:"results"`
		Error   string       `json:"error"`
	}

	mr := multiResult{
		Count:   len(results),
		Elapsed: elapsed,
		Results: results,
	}

	setProgress(fmt.Sprintf("扫描完成，用时 %d 秒，共 %d 个结果", elapsed, len(results)))

	b, _ := json.Marshal(mr)
	return string(b)
}

// UpdateData 刷新数据
func UpdateData() {
	setProgress("正在更新数据...")
	_, err := fetchPoolFromServer(true, true, "")
	if err != nil {
		setProgress("更新失败: " + err.Error())
		return
	}
	setProgress("数据更新完成")
}
