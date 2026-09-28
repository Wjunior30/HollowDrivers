$MainXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="HollowDrivers" Width="1120" Height="760" MinWidth="980" MinHeight="640" WindowStartupLocation="CenterScreen"
        Background="{StaticResource Bg}" Foreground="{StaticResource Text}" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13"
        UseLayoutRounding="True">
  <Grid>
    <!-- ======================= INÍCIO ======================= -->
    <Grid x:Name="HomeView">
      <Grid.Background>
        <RadialGradientBrush Center="0.5,0.3" GradientOrigin="0.5,0.3" RadiusX="0.6" RadiusY="0.65">
          <GradientStop Color="__BGR__" Offset="0"/>
          <GradientStop Color="#0F1115" Offset="1"/>
        </RadialGradientBrush>
      </Grid.Background>
      <DockPanel>
        <Border x:Name="HomeRail" DockPanel.Dock="Left" Width="228" Background="#12151B" BorderBrush="{StaticResource Stroke}" BorderThickness="0,0,1,0">
          <DockPanel x:Name="HomeRailBox" Margin="14,18,14,14">
            <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="10,0,0,24">
              <Image x:Name="BrandLogo1" Width="32" Height="32" Stretch="Uniform" VerticalAlignment="Center" Margin="0,0,9,0"/>
              <TextBlock x:Name="HomeLogoText" Text="HollowDrivers" FontSize="16" FontWeight="SemiBold" FontFamily="{StaticResource Display}" VerticalAlignment="Center"/>
            </StackPanel>
            <Button x:Name="BtnRailHome" DockPanel.Dock="Top" Style="{StaticResource NavBtn}" Tag="&#xE700;" Content="Recolher menu" Margin="0,0,0,6" HorizontalAlignment="Left"/>
            <Button x:Name="BtnHomeScan" DockPanel.Dock="Bottom" Style="{StaticResource NavBtn}" Tag="&#xE721;" Content="Analisar agora"/>
            <StackPanel>
              <ToggleButton x:Name="HomeNavHome" Style="{StaticResource Nav}" Tag="&#xE80F;" Content="Início" IsChecked="True"/>
              <Button x:Name="BtnAdvanced" Style="{StaticResource NavBtn}" Tag="&#xE896;" Content="Drivers"/>
              <Button x:Name="HomeNavVideo" Style="{StaticResource NavBtn}" Tag="&#xE7F4;" Content="Meus drivers"/>
              <Button x:Name="HomeNavWin" Style="{StaticResource NavBtn}" Tag="&#xE895;" Content="Windows Update"/>
              <Button x:Name="HomeNavSystem" Style="{StaticResource NavBtn}" Tag="&#xE946;" Content="Sistema"/>
              <Button x:Name="HomeNavGuard" Style="{StaticResource NavBtn}" Tag="&#xEA18;" Content="Proteção"/>
              <Button x:Name="HomeNavClean" Style="{StaticResource NavBtn}" Tag="&#xE74D;" Content="Limpeza"/>
              <Button x:Name="BtnHomeConfig" Style="{StaticResource NavBtn}" Tag="&#xE713;" Content="Configurações"/>
            </StackPanel>
          </DockPanel>
        </Border>
        <Grid DockPanel.Dock="Bottom" Margin="28,0,28,16">
          <TextBlock x:Name="FooterText" Foreground="{StaticResource Dim}" FontSize="12" VerticalAlignment="Center"/>
        </Grid>
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,30,0,20" Width="720">
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
              <Image x:Name="BrandLogo2" Width="32" Height="32" Stretch="Uniform" VerticalAlignment="Center" Margin="0,0,9,0"/>
              <TextBlock Text="HollowDrivers" FontSize="30" FontWeight="SemiBold" FontFamily="{StaticResource Display}"/>
            </StackPanel>
            <TextBlock Text="Verifica seus drivers e avisa quando algo der errado." Foreground="{StaticResource Dim}" FontSize="14" HorizontalAlignment="Center" Margin="0,6,0,0"/>

            <Button x:Name="BigBtn" Width="220" Height="220" Margin="0,40,0,36" Cursor="Hand" HorizontalAlignment="Center" Focusable="False">
              <Button.Template>
                <ControlTemplate TargetType="Button">
                  <Grid x:Name="Root" RenderTransformOrigin="0.5,0.5">
                    <Grid.RenderTransform><ScaleTransform x:Name="Sc" ScaleX="1" ScaleY="1"/></Grid.RenderTransform>
                    <Ellipse Fill="__HALO__" Margin="-18"/>
                    <Ellipse Fill="{StaticResource Accent}">
                      <Ellipse.Effect><DropShadowEffect Color="__GLOW__" BlurRadius="70" ShadowDepth="0" Opacity="0.55"/></Ellipse.Effect>
                    </Ellipse>
                    <Ellipse Margin="12" Stroke="#40FFFFFF" StrokeThickness="1.5"/>
                    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Grid>
                  <ControlTemplate.Triggers>
                    <Trigger Property="IsMouseOver" Value="True">
                      <Trigger.EnterActions>
                        <BeginStoryboard>
                          <Storyboard>
                            <DoubleAnimation Storyboard.TargetName="Sc" Storyboard.TargetProperty="ScaleX" To="1.05" Duration="0:0:0.18"/>
                            <DoubleAnimation Storyboard.TargetName="Sc" Storyboard.TargetProperty="ScaleY" To="1.05" Duration="0:0:0.18"/>
                          </Storyboard>
                        </BeginStoryboard>
                      </Trigger.EnterActions>
                      <Trigger.ExitActions>
                        <BeginStoryboard>
                          <Storyboard>
                            <DoubleAnimation Storyboard.TargetName="Sc" Storyboard.TargetProperty="ScaleX" To="1" Duration="0:0:0.18"/>
                            <DoubleAnimation Storyboard.TargetName="Sc" Storyboard.TargetProperty="ScaleY" To="1" Duration="0:0:0.18"/>
                          </Storyboard>
                        </BeginStoryboard>
                      </Trigger.ExitActions>
                    </Trigger>
                    <Trigger Property="IsPressed" Value="True"><Setter TargetName="Root" Property="Opacity" Value="0.85"/></Trigger>
                  </ControlTemplate.Triggers>
                </ControlTemplate>
              </Button.Template>
              <Grid Width="220" Height="220">
                <Ellipse x:Name="Spinner" Margin="5" Stroke="White" StrokeThickness="4" StrokeDashArray="30 200" StrokeDashCap="Round" Opacity="0" RenderTransformOrigin="0.5,0.5">
                  <Ellipse.RenderTransform><RotateTransform x:Name="SpinRot"/></Ellipse.RenderTransform>
                </Ellipse>
                <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
                  <TextBlock x:Name="BigIcon" FontFamily="{StaticResource Icons}" Text="&#xE721;" FontSize="36" Foreground="White" HorizontalAlignment="Center"/>
                  <TextBlock x:Name="BigLabel" Text="ANALISAR" FontSize="24" FontWeight="Bold" Foreground="White" HorizontalAlignment="Center" Margin="0,8,0,0" FontFamily="{StaticResource Display}"/>
                </StackPanel>
              </Grid>
            </Button>

            <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
              <Border x:Name="VerdictBadge" Width="38" Height="38" CornerRadius="19" Background="#1F232C" Margin="0,0,12,0">
                <TextBlock x:Name="VerdictIcon" FontFamily="{StaticResource Icons}" Text="&#xE946;" FontSize="17" Foreground="{StaticResource Dim}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <TextBlock x:Name="VerdictText" Text="Pronto para verificar" FontSize="24" FontWeight="SemiBold" VerticalAlignment="Center" FontFamily="{StaticResource Display}"/>
            </StackPanel>
            <TextBlock x:Name="VerdictSub" Text="Clique no botão para analisar seu PC" Foreground="{StaticResource Dim}" HorizontalAlignment="Center" Margin="0,8,0,0" FontSize="13"/>
            <StackPanel x:Name="Findings" Margin="0,26,0,0"/>
          </StackPanel>
        </ScrollViewer>
      </DockPanel>
    </Grid>

    <!-- ======================= AVANÇADO ======================= -->
    <Grid x:Name="AdvView" Visibility="Collapsed">
      <Grid.ColumnDefinitions>
        <ColumnDefinition x:Name="AdvCol" Width="228"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <!-- ===== barra lateral ===== -->
      <Border Background="#12151B" BorderBrush="{StaticResource Stroke}" BorderThickness="0,0,1,0">
        <DockPanel x:Name="AdvRailBox" Margin="14,18,14,14">
          <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="10,0,0,24">
            <Image x:Name="BrandLogo3" Width="32" Height="32" Stretch="Uniform" VerticalAlignment="Center" Margin="0,0,9,0"/>
            <TextBlock x:Name="AdvLogoText" Text="HollowDrivers" FontSize="16" FontWeight="SemiBold" FontFamily="{StaticResource Display}" VerticalAlignment="Center"/>
          </StackPanel>
          <Button x:Name="BtnRailAdv" DockPanel.Dock="Top" Style="{StaticResource NavBtn}" Tag="&#xE700;" Content="Recolher menu" Margin="0,0,0,6" HorizontalAlignment="Left"/>
          <StackPanel>
            <Button x:Name="BtnBack" Style="{StaticResource NavBtn}" Tag="&#xE80F;" Content="Início"/>
            <ToggleButton x:Name="NavDrivers" Style="{StaticResource Nav}" Tag="&#xE896;" Content="Drivers" IsChecked="True"/>
            <ToggleButton x:Name="NavVideo" Style="{StaticResource Nav}" Tag="&#xE7F4;" Content="Meus drivers"/>
            <ToggleButton x:Name="NavWin" Style="{StaticResource Nav}" Tag="&#xE895;" Content="Windows Update"/>
            <ToggleButton x:Name="NavSystem" Style="{StaticResource Nav}" Tag="&#xE946;" Content="Sistema"/>
            <ToggleButton x:Name="NavGuard" Style="{StaticResource Nav}" Tag="&#xEA18;" Content="Proteção"/>
            <ToggleButton x:Name="NavClean" Style="{StaticResource Nav}" Tag="&#xE74D;" Content="Limpeza"/>
            <Button x:Name="BtnAdvConfig" Style="{StaticResource NavBtn}" Tag="&#xE713;" Content="Configurações"/>

          </StackPanel>
        </DockPanel>
      </Border>

      <!-- ===== seção: Drivers ===== -->
      <Grid x:Name="PanDrivers" Grid.Column="1" Margin="26,20,26,14">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <StackPanel>
          <TextBlock Text="Drivers" Style="{StaticResource SectionTitle}"/>
          <TextBlock Text="Tudo que está instalado no seu PC, com o estado de cada driver." Style="{StaticResource SectionSub}"/>
          <WrapPanel Margin="0,16,0,0">
            <WrapPanel.Resources><Style TargetType="Button" BasedOn="{StaticResource Pill}"/></WrapPanel.Resources>
            <Button x:Name="BtnScan" Style="{StaticResource PillAccent}" Content="Escanear"/>
            <Button x:Name="BtnUpd" Content="Atualizar drivers"/>
            <Button x:Name="BtnAll" Content="Exportar para pendrive"/>
            <Button x:Name="BtnWu" Content="Windows Update"/>
          </WrapPanel>
        </StackPanel>

        <StackPanel Grid.Row="1" Margin="0,10,0,10">
          <StackPanel Orientation="Horizontal">
            <ToggleButton x:Name="ChipAll" Style="{StaticResource Chip}" Tag="all" Content="Todos" IsChecked="True"/>
            <ToggleButton x:Name="ChipBad" Style="{StaticResource Chip}" Tag="bad" Content="Com problema"/>
            <ToggleButton x:Name="ChipOld" Style="{StaticResource Chip}" Tag="old" Content="Antigos"/>
            <ToggleButton x:Name="ChipVideo" Style="{StaticResource Chip}" Tag="Vídeo" Content="Vídeo"/>
            <ToggleButton x:Name="ChipNet" Style="{StaticResource Chip}" Tag="Rede" Content="Rede"/>
            <ToggleButton x:Name="ChipAudio" Style="{StaticResource Chip}" Tag="Áudio" Content="Áudio"/>
            <Border Width="250" Margin="10,0,0,0" Background="{StaticResource Surface2}" BorderBrush="{StaticResource Stroke}" BorderThickness="1" CornerRadius="14" Padding="13,4">
              <DockPanel>
                <TextBlock DockPanel.Dock="Left" FontFamily="{StaticResource Icons}" Text="&#xE721;" Foreground="{StaticResource Dim}" VerticalAlignment="Center" Margin="0,0,9,0" FontSize="12"/>
                <TextBox x:Name="SearchBox"/>
              </DockPanel>
            </Border>
          </StackPanel>
          <CheckBox x:Name="ChkMs" Content="Mostrar drivers genéricos da Microsoft" Margin="2,12,0,0"/>
        </StackPanel>

      <Border Grid.Row="2" Background="{StaticResource Surface}" BorderBrush="{StaticResource Stroke}" BorderThickness="1" CornerRadius="14" Padding="4">
       <Grid>
        <TextBlock x:Name="EmptyText" Visibility="Collapsed" HorizontalAlignment="Center" VerticalAlignment="Center" TextAlignment="Center" Foreground="{StaticResource Dim}" FontSize="13.5"/>
        <DataGrid x:Name="DriverGrid" AutoGenerateColumns="False">
          <DataGrid.Columns>
            <DataGridTemplateColumn Header="Status" SortMemberPath="Ordem" Width="175">
              <DataGridTemplateColumn.CellTemplate>
                <DataTemplate>
                  <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <Ellipse Width="8" Height="8" Fill="{Binding Cor}" Margin="0,0,9,0"/>
                    <TextBlock Text="{Binding Status}" Foreground="{Binding Cor}" FontWeight="SemiBold"/>
                  </StackPanel>
                </DataTemplate>
              </DataGridTemplateColumn.CellTemplate>
            </DataGridTemplateColumn>
            <DataGridTextColumn Header="Categoria" Binding="{Binding Categoria}" Width="130"/>
            <DataGridTextColumn Header="Dispositivo" Binding="{Binding Dispositivo}" Width="*"/>
            <DataGridTextColumn Header="Fabricante" Binding="{Binding Fabricante}" Width="170"/>
            <DataGridTextColumn Header="Versão" Binding="{Binding Versao}" Width="130"/>
            <DataGridTextColumn Header="Data" Binding="{Binding Data, StringFormat=dd/MM/yyyy}" Width="95"/>
            <DataGridTextColumn Header="Idade" Binding="{Binding Idade}" Width="65"/>
            <DataGridTextColumn Header="INF" Binding="{Binding INF}" Width="95"/>
          </DataGrid.Columns>
        </DataGrid>
       </Grid>
      </Border>

      <TextBlock Grid.Row="3" x:Name="StatusText" Foreground="{StaticResource Dim}" FontSize="12" Margin="4,10,0,0"/>
      </Grid>

      <!-- ===== seção: Meus drivers ===== -->
       <Grid x:Name="PanVideo" Grid.Column="1" Margin="26,20,26,14" Visibility="Collapsed">
         <Grid.RowDefinitions>
           <RowDefinition Height="Auto"/>
           <RowDefinition Height="Auto"/>
           <RowDefinition Height="*"/>
         </Grid.RowDefinitions>
         <StackPanel>
           <TextBlock Text="Meus drivers" Style="{StaticResource SectionTitle}"/>
           <TextBlock Text="Cada driver tem sua própria cópia. Veja o que já está protegido e faça backup dos que faltam." Style="{StaticResource SectionSub}"/>
         </StackPanel>
         <Border Grid.Row="1" Margin="0,18,0,0" Background="{StaticResource Surface2}" BorderBrush="{StaticResource Stroke}" BorderThickness="1" CornerRadius="14" Padding="20,16">
           <Grid>
             <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
             <StackPanel>
               <TextBlock Text="PROTEÇÃO DOS DRIVERS" Style="{StaticResource GroupLbl}"/>
               <TextBlock x:Name="KeyCoverage" Text="Verificando cópias..." FontSize="22" FontWeight="SemiBold" FontFamily="{StaticResource Display}" Margin="0,3,0,2"/>
               <TextBlock x:Name="KeyResumo" Foreground="{StaticResource Dim}" FontSize="12.5"/>
             </StackPanel>
             <Button Grid.Column="1" x:Name="BtnKeyAll" Style="{StaticResource PillAccent}" Content="Fazer backup dos que faltam" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="18,0,0,0" Padding="18,10"/>
           </Grid>
         </Border>
         <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" Margin="0,16,0,0">
           <StackPanel>
             <Grid>
               <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
               <Border Background="{StaticResource Surface}" BorderBrush="{StaticResource Stroke}" BorderThickness="1" CornerRadius="14" Padding="20,16">
                 <StackPanel>
                   <TextBlock x:Name="GpuText" TextWrapping="Wrap" LineHeight="22"/>
                   <WrapPanel Margin="0,12,0,0">
                     <WrapPanel.Resources><Style TargetType="Button" BasedOn="{StaticResource Pill}"/></WrapPanel.Resources>
                     <Button x:Name="BtnGood" Style="{StaticResource PillAccent}" Content="Fazer backup"/>
                     <Button x:Name="BtnRestore" Content="Restaurar"/>
                     <Button x:Name="BtnHist" Content="Histórico"/>
                     <Button x:Name="BtnEnable" Style="{StaticResource PillAccent}" Content="Reativar placa" Visibility="Collapsed"/>
                   </WrapPanel>
                 </StackPanel>
               </Border>
               <Border Grid.Column="1" Margin="16,0,0,0" Background="{StaticResource Surface}" BorderBrush="{StaticResource Stroke}" BorderThickness="1" CornerRadius="14" Padding="20,16">
                 <TextBlock x:Name="SysText" TextWrapping="Wrap" LineHeight="22"/>
               </Border>
             </Grid>
             <StackPanel Margin="0,24,0,0">
               <TextBlock Text="OUTROS DRIVERS" Style="{StaticResource GroupLbl}"/>
               <TextBlock Text="O estado e a cópia de cada driver aparecem separadamente." Foreground="{StaticResource Dim}" FontSize="12.5" Margin="0,1,0,12"/>
               <WrapPanel x:Name="KeyCards"/>
             </StackPanel>
             <Expander Header="Ver lista técnica completa" Foreground="{StaticResource Text}" FontWeight="SemiBold" Margin="0,8,0,20">
               <Border Margin="0,12,0,0" Background="{StaticResource Surface}" BorderBrush="{StaticResource Stroke}" BorderThickness="1" CornerRadius="14" Padding="4">
                 <DataGrid x:Name="KeyGrid" AutoGenerateColumns="False" Height="320">
                   <DataGrid.Columns>
                     <DataGridTemplateColumn Header="Situação" Width="190">
                       <DataGridTemplateColumn.CellTemplate>
                         <DataTemplate>
                           <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                             <Ellipse Width="8" Height="8" Fill="{Binding Cor}" Margin="0,0,9,0"/>
                             <TextBlock Text="{Binding Estado}" Foreground="{Binding Cor}" FontWeight="SemiBold"/>
                           </StackPanel>
                         </DataTemplate>
                       </DataGridTemplateColumn.CellTemplate>
                     </DataGridTemplateColumn>
                     <DataGridTextColumn Header="Categoria" Binding="{Binding Categoria}" Width="120"/>
                     <DataGridTextColumn Header="Dispositivo" Binding="{Binding Nome}" Width="*"/>
                     <DataGridTextColumn Header="Fabricante" Binding="{Binding Fabricante}" Width="160"/>
                     <DataGridTextColumn Header="Versão" Binding="{Binding Versao}" Width="130"/>
                     <DataGridTextColumn Header="Cópia salva" Binding="{Binding Backup}" Width="120"/>
                   </DataGrid.Columns>
                 </DataGrid>
               </Border>
             </Expander>
           </StackPanel>
         </ScrollViewer>
       </Grid>
       <!-- ===== seção: Sistema ===== -->
      <Grid x:Name="PanSystem" Grid.Column="1" Margin="26,20,26,14" Visibility="Collapsed">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <StackPanel>
          <TextBlock Text="Sistema" Style="{StaticResource SectionTitle}"/>
          <TextBlock Text="Saúde do PC, ponto de restauração e os sites oficiais do seu hardware." Style="{StaticResource SectionSub}"/>
        </StackPanel>
        <Border Grid.Row="1" Margin="0,18,0,0" MaxWidth="720" HorizontalAlignment="Left" Background="{StaticResource Surface}" BorderBrush="{StaticResource Stroke}" BorderThickness="1" CornerRadius="14" Padding="22,18">
          <TextBlock x:Name="HealthText" TextWrapping="Wrap" LineHeight="23"/>
        </Border>
        <WrapPanel Grid.Row="2" Margin="0,16,0,0">
          <WrapPanel.Resources><Style TargetType="Button" BasedOn="{StaticResource Pill}"/></WrapPanel.Resources>
          <Button x:Name="BtnCrash" Style="{StaticResource PillAccent}" Content="Quedas do PC"/>
          <Button x:Name="BtnPoint" Content="Criar ponto de restauração"/>
          <Button x:Name="BtnSites" Content="Sites oficiais  ▾"/>
          <Button x:Name="BtnCsv" Content="Exportar CSV"/>

        </WrapPanel>
        <Popup x:Name="SitesPopup" PlacementTarget="{Binding ElementName=BtnSites}" Placement="Bottom" StaysOpen="False" AllowsTransparency="True" VerticalOffset="2">
          <Border Background="{StaticResource Surface2}" BorderBrush="{StaticResource Stroke}" BorderThickness="1" CornerRadius="12" Padding="6">
            <StackPanel x:Name="SitesList"/>
          </Border>
        </Popup>
      <Border Grid.Row="3" Margin="0,22,0,0" MaxWidth="720" HorizontalAlignment="Left" VerticalAlignment="Top"
                 Background="{StaticResource Surface}" BorderBrush="{StaticResource Stroke}" BorderThickness="1" CornerRadius="14" Padding="22,18">
           <StackPanel>
             <TextBlock Text="LIBERAR ESPAÇO" Style="{StaticResource GroupLbl}"/>
             <TextBlock x:Name="StorageText" FontSize="18" FontWeight="SemiBold" FontFamily="{StaticResource Display}" Margin="0,3,0,8"/>
             <TextBlock Text="Analise arquivos temporários e logs antigos aqui. Para aplicativos e arquivos grandes, use a limpeza oficial do Windows."
                        TextWrapping="Wrap" Foreground="{StaticResource Dim}" FontSize="12.5"/>
             <WrapPanel Margin="0,14,0,0">
               <WrapPanel.Resources><Style TargetType="Button" BasedOn="{StaticResource Pill}"/></WrapPanel.Resources>
               <Button x:Name="BtnCleanup" Style="{StaticResource PillAccent}" Content="Abrir Limpeza"/>
               <Button x:Name="BtnStorageSense" Content="Configurar limpeza automática"/>
             </WrapPanel>
           </StackPanel>
         </Border>
       </Grid>

      <!-- ===== seção: Limpeza ===== -->
      <Grid x:Name="PanClean" Grid.Column="1" Margin="26,20,26,14" Visibility="Collapsed">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <StackPanel>
          <TextBlock Text="Limpeza" Style="{StaticResource SectionTitle}"/>
          <TextBlock Text="Revise arquivos antigos e escolha o que deseja remover." Style="{StaticResource SectionSub}"/>
        </StackPanel>
        <Border Grid.Row="1" Margin="0,18,0,16" Background="{StaticResource Surface}" BorderBrush="{StaticResource Stroke}" BorderThickness="1" CornerRadius="14" Padding="20,16">
          <StackPanel>
            <TextBlock x:Name="CleanDrive" FontSize="17" FontWeight="SemiBold" FontFamily="{StaticResource Display}"/>
            <TextBlock x:Name="CleanSummary" Text="Clique em Analisar para procurar arquivos antigos." Foreground="{StaticResource Dim}" Margin="0,7,0,0" TextWrapping="Wrap"/>
          </StackPanel>
        </Border>
        <Border Grid.Row="2" Background="{StaticResource Surface}" BorderBrush="{StaticResource Stroke}" BorderThickness="1" CornerRadius="14" Padding="12" MinHeight="230">
          <DataGrid x:Name="CleanGrid" AutoGenerateColumns="False" CanUserAddRows="False" IsReadOnly="False" HeadersVisibility="Column">
            <DataGrid.Columns>
              <DataGridCheckBoxColumn Header="Limpar" Binding="{Binding Select, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}" Width="76"/>
              <DataGridTextColumn Header="Categoria" Binding="{Binding Category}" IsReadOnly="True" Width="190"/>
              <DataGridTextColumn Header="Arquivos" Binding="{Binding Count}" IsReadOnly="True" Width="90"/>
              <DataGridTextColumn Header="Espaço" Binding="{Binding Size}" IsReadOnly="True" Width="100"/>
              <DataGridTextColumn Header="Descrição" Binding="{Binding Description}" IsReadOnly="True" Width="*"/>
            </DataGrid.Columns>
          </DataGrid>
        </Border>
        <StackPanel Grid.Row="3" Margin="0,16,0,0">
          <WrapPanel>
            <Button x:Name="BtnCleanScan" Style="{StaticResource Pill}" Content="Analisar"/>
            <Button x:Name="BtnCleanRun" Style="{StaticResource PillAccent}" Content="Limpar selecionados" IsEnabled="False"/>
            <Button x:Name="BtnCleanWindows" Style="{StaticResource Pill}" Content="Limpeza do Windows"/>
            <Button x:Name="BtnCleanSense" Style="{StaticResource Pill}" Content="Limpeza automática"/>
          </WrapPanel>
          <TextBlock x:Name="CleanStatus" Text="Arquivos em uso e dados de backup são preservados." Foreground="{StaticResource Dim}" FontSize="12" Margin="2,10,0,0" TextWrapping="Wrap"/>
        </StackPanel>
      </Grid>
      <!-- ===== seção: Windows Update ===== -->
      <Grid x:Name="PanWin" Grid.Column="1" Margin="26,20,26,14" Visibility="Collapsed">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <StackPanel>
          <TextBlock Text="Windows Update" Style="{StaticResource SectionTitle}"/>
          <TextBlock Text="Controle o que o Windows instala sozinho e guarde um ponto para voltar se algo quebrar." Style="{StaticResource SectionSub}"/>
        </StackPanel>
        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="0,18,0,0">
          <StackPanel MaxWidth="760" HorizontalAlignment="Left">
        <Border MaxWidth="760" Background="{StaticResource Surface}" BorderBrush="{StaticResource Stroke}" BorderThickness="1" CornerRadius="14" Padding="22,18">
          <StackPanel>
            <TextBlock Text="ATUALIZAÇÕES DO WINDOWS" Style="{StaticResource GroupLbl}"/>
            <TextBlock x:Name="WuText" TextWrapping="Wrap" LineHeight="22"/>
            <WrapPanel Margin="0,14,0,0">
              <WrapPanel.Resources><Style TargetType="Button" BasedOn="{StaticResource Pill}"/></WrapPanel.Resources>
              <Button x:Name="BtnWuHold" Style="{StaticResource PillAccent}" Content="Segurar atualizações"/>
              <Button x:Name="BtnWuKeep" Content="Manter segurado"/>
              <Button x:Name="BtnWuDrv" Content="Bloquear troca de drivers"/>
            </WrapPanel>
          </StackPanel>
        </Border>
        <Border Margin="0,16,0,0" MaxWidth="760" Background="{StaticResource Surface}" BorderBrush="{StaticResource Stroke}" BorderThickness="1" CornerRadius="14" Padding="22,18">
          <StackPanel>
            <TextBlock Text="PONTOS DE RESTAURAÇÃO DO WINDOWS" Style="{StaticResource GroupLbl}"/>
            <TextBlock x:Name="SrText" TextWrapping="Wrap" LineHeight="22"/>
            <WrapPanel Margin="0,14,0,0">
              <WrapPanel.Resources><Style TargetType="Button" BasedOn="{StaticResource Pill}"/></WrapPanel.Resources>
              <Button x:Name="BtnSrPoint" Style="{StaticResource PillAccent}" Content="Criar ponto de restauração"/>
              <Button x:Name="BtnSrOpen" Content="Restaurar o Windows"/>
            </WrapPanel>
          </StackPanel>
        </Border>
          </StackPanel>
        </ScrollViewer>
      </Grid>

      <!-- ===== seção: Proteção ===== -->
      <Grid x:Name="PanGuard" Grid.Column="1" Margin="26,20,26,14" Visibility="Collapsed">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <StackPanel>
          <TextBlock Text="Proteção" Style="{StaticResource SectionTitle}"/>
          <TextBlock Text="O HollowDrivers vigiando seu PC em segundo plano." Style="{StaticResource SectionSub}"/>
        </StackPanel>
        <Border Grid.Row="1" Margin="0,18,0,0" MaxWidth="720" HorizontalAlignment="Left" Background="{StaticResource Surface}" BorderBrush="{StaticResource Stroke}" BorderThickness="1" CornerRadius="14" Padding="22,18">
          <TextBlock x:Name="GuardText" TextWrapping="Wrap" LineHeight="23"/>
        </Border>
        <WrapPanel Grid.Row="2" Margin="0,16,0,0">
          <WrapPanel.Resources><Style TargetType="Button" BasedOn="{StaticResource Pill}"/></WrapPanel.Resources>
          <Button x:Name="BtnWatch" Style="{StaticResource PillAccent}" Content="Vigia automático"/>
          <Button x:Name="BtnRescue" Content="Socorro automático"/>
          <Button x:Name="BtnClone" Content="Preparar clone do Windows"/><Button x:Name="BtnHistory" Content="Histórico"/><Button x:Name="BtnDiagnostics" Content="Exportar diagnóstico"/>
          <Button x:Name="BtnDb" Style="{StaticResource PillBad}" Content="Remover Driver Booster" Visibility="Collapsed"/>
        </WrapPanel>
      </Grid>
    </Grid>

    <!-- ======================= CONFIGURAÇÕES ======================= -->
    <Grid x:Name="ConfigView" Background="{StaticResource Bg}" Visibility="Collapsed">
      <Grid.ColumnDefinitions>
        <ColumnDefinition x:Name="ConfigCol" Width="228"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>
      <Border Grid.RowSpan="2" Background="#12151B" BorderBrush="{StaticResource Stroke}" BorderThickness="0,0,1,0">
        <DockPanel x:Name="ConfigRailBox" Margin="14,18,14,14">
          <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="10,0,0,24">
            <Image x:Name="BrandLogo4" Width="32" Height="32" Stretch="Uniform" VerticalAlignment="Center" Margin="0,0,9,0"/>
            <TextBlock x:Name="ConfigLogoText" Text="HollowDrivers" FontSize="16" FontWeight="SemiBold" FontFamily="{StaticResource Display}" VerticalAlignment="Center"/>
          </StackPanel>
          <Button x:Name="BtnRailConfig" DockPanel.Dock="Top" Style="{StaticResource NavBtn}" Tag="&#xE700;" Content="Recolher menu" Margin="0,0,0,6" HorizontalAlignment="Left"/>
          <StackPanel>
            <Button x:Name="BtnConfigHome" Style="{StaticResource NavBtn}" Tag="&#xE80F;" Content="Início"/>
            <Button x:Name="ConfigNavDrivers" Style="{StaticResource NavBtn}" Tag="&#xE896;" Content="Drivers"/>
            <Button x:Name="ConfigNavVideo" Style="{StaticResource NavBtn}" Tag="&#xE7F4;" Content="Meus drivers"/>
            <Button x:Name="ConfigNavWin" Style="{StaticResource NavBtn}" Tag="&#xE895;" Content="Windows Update"/>
            <Button x:Name="ConfigNavSystem" Style="{StaticResource NavBtn}" Tag="&#xE946;" Content="Sistema"/>
            <Button x:Name="ConfigNavGuard" Style="{StaticResource NavBtn}" Tag="&#xEA18;" Content="Proteção"/>
            <Button x:Name="ConfigNavClean" Style="{StaticResource NavBtn}" Tag="&#xE74D;" Content="Limpeza"/>
            <ToggleButton x:Name="ConfigNavSettings" Style="{StaticResource Nav}" Tag="&#xE713;" Content="Configurações" IsChecked="True"/>
          </StackPanel>
        </DockPanel>
      </Border>
      <Grid Grid.Column="1" Margin="30,22,30,0">
        <StackPanel>
          <TextBlock Text="Configurações" Style="{StaticResource SectionTitle}"/>
          <TextBlock Text="Aparência do app e atualizações do próprio HollowDrivers." Style="{StaticResource SectionSub}"/>
        </StackPanel>
        <Button x:Name="BtnConfigClose" Style="{StaticResource NavBtn}" Tag="&#xE711;" Content="Fechar" HorizontalAlignment="Right" VerticalAlignment="Top"/>
      </Grid>
      <ScrollViewer Grid.Column="1" Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="30,18,30,22">
        <StackPanel MaxWidth="760" HorizontalAlignment="Left">
        <Border Margin="0,18,0,0" MaxWidth="760" Background="{StaticResource Surface}" BorderBrush="{StaticResource Stroke}" BorderThickness="1" CornerRadius="14" Padding="22,18">
          <StackPanel>
            <TextBlock Text="TEMA DE CORES" Style="{StaticResource GroupLbl}"/>
            <TextBlock Text="A cor de destaque do app. Ao trocar, o HollowDrivers reabre em um segundo." Foreground="{StaticResource Dim}" FontSize="12.5" Margin="0,0,0,14"/>
            <WrapPanel x:Name="ConfigThemes"/>
          </StackPanel>
        </Border>
        <Border Margin="0,16,0,0" MaxWidth="760" Background="{StaticResource Surface}" BorderBrush="{StaticResource Stroke}" BorderThickness="1" CornerRadius="14" Padding="22,18">
          <StackPanel>
            <TextBlock Text="ATUALIZAÇÕES DO HollowDrivers" Style="{StaticResource GroupLbl}"/>
            <TextBlock x:Name="ConfigUpd" TextWrapping="Wrap" LineHeight="22"/>
            <WrapPanel Margin="0,14,0,0">
              <WrapPanel.Resources><Style TargetType="Button" BasedOn="{StaticResource Pill}"/></WrapPanel.Resources>
              <Button x:Name="BtnAppCheck" Content="Procurar atualização"/>
              <Button x:Name="BtnAppInstall" Style="{StaticResource PillAccent}" Content="Instalar atualização" Visibility="Collapsed"/>
            </WrapPanel>
          </StackPanel>
        </Border>
        </StackPanel>
      </ScrollViewer>
    </Grid>
  </Grid>
</Window>
'@

$DialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" SizeToContent="Height" Width="500"
        WindowStartupLocation="CenterOwner" ShowInTaskbar="False" ResizeMode="NoResize"
        FontFamily="Segoe UI Variable Text, Segoe UI" Foreground="{StaticResource Text}">
  <Border Background="{StaticResource Surface}" BorderBrush="{StaticResource Stroke}" BorderThickness="1" CornerRadius="16" Padding="24,22" Margin="20">
    <Border.Effect><DropShadowEffect BlurRadius="30" ShadowDepth="0" Opacity="0.6"/></Border.Effect>
    <StackPanel>
      <StackPanel Orientation="Horizontal">
        <Border x:Name="Badge" Width="36" Height="36" CornerRadius="18">
          <TextBlock x:Name="Ico" FontFamily="{StaticResource Icons}" FontSize="16" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <TextBlock x:Name="Head" FontSize="17" FontWeight="SemiBold" VerticalAlignment="Center" Margin="12,0,0,0" FontFamily="{StaticResource Display}"/>
      </StackPanel>
      <TextBlock x:Name="Body" TextWrapping="Wrap" Margin="0,14,0,22" Foreground="#C9CED6" LineHeight="21" FontSize="13.5"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="No" Style="{StaticResource Pill}" Content="Cancelar" Visibility="Collapsed" IsCancel="True"/>
        <Button x:Name="Yes" Style="{StaticResource PillAccent}" Content="OK" Margin="0" IsDefault="True"/>
      </StackPanel>
    </StackPanel>
  </Border>
</Window>
'@

$TableXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="940" Height="500" WindowStartupLocation="CenterOwner" ShowInTaskbar="False"
        Background="{StaticResource Bg}" Foreground="{StaticResource Text}" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13">
  <Grid Margin="22,18,22,18">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock x:Name="Head" FontSize="19" FontWeight="SemiBold" FontFamily="{StaticResource Display}"/>
    <Border Grid.Row="1" Margin="0,14,0,14" Background="{StaticResource Surface}" BorderBrush="{StaticResource Stroke}" BorderThickness="1" CornerRadius="14" Padding="4">
      <DataGrid x:Name="G" AutoGenerateColumns="True">
        <DataGrid.RowStyle>
          <Style TargetType="DataGridRow" BasedOn="{StaticResource {x:Type DataGridRow}}">
            <Style.Triggers>
              <DataTrigger Binding="{Binding Destaque}" Value="True"><Setter Property="Foreground" Value="#F87171"/></DataTrigger>
            </Style.Triggers>
          </Style>
        </DataGrid.RowStyle>
      </DataGrid>
    </Border>
    <DockPanel Grid.Row="2">
      <Button x:Name="Close" DockPanel.Dock="Right" Style="{StaticResource PillAccent}" Content="Fechar" Margin="12,0,0,0" IsCancel="True"/>
      <TextBlock x:Name="Note" TextWrapping="Wrap" Foreground="{StaticResource Dim}" VerticalAlignment="Center"/>
    </DockPanel>
  </Grid>
</Window>
'@

